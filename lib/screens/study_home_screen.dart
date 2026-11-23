import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'study_history_screen.dart';
import 'review_selection_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'subject_management_screen.dart';
import 'study_analysis_screen.dart';
import 'exam_management_screen.dart';
import 'exam_date_utils.dart';
import 'profile_setup_screen.dart';
import '../services/study_storage.dart';

const _lavender = Color(0xFF8576D8);
const _ink = Color(0xFF242B50);

class HomeExam {
  const HomeExam({required this.id, required this.title, required this.date,
    required this.semesterCode, required this.subjectId});
  final String id;
  final String title;
  final DateTime? date;
  final String? semesterCode;
  final String? subjectId;
}

HomeExam? nearestHomeExam(Iterable<HomeExam> exams, DateTime now) {
  final eligible = exams.where((exam) =>
      exam.date != null && daysUntilExam(exam.date, now: now)! >= 0).toList();
  eligible.sort((a, b) {
    final byDay = daysUntilExam(a.date, now: now)!
        .compareTo(daysUntilExam(b.date, now: now)!);
    return byDay != 0 ? byDay : a.id.compareTo(b.id);
  });
  return eligible.isEmpty ? null : eligible.first;
}

class ExamStatusCard extends StatefulWidget {
  const ExamStatusCard({super.key, required this.uid, this.exams,
    this.subjectLoader, this.statsLoader, this.countLoader});
  final String uid;
  final Stream<List<HomeExam>>? exams;
  final Future<String> Function(String, String)? subjectLoader;
  final Future<Map<String, dynamic>> Function(String, String)? statsLoader;
  final Future<int> Function(String, String)? countLoader;

  @override
  ExamStatusCardState createState() => ExamStatusCardState();
}

class ExamStatusCardState extends State<ExamStatusCard> with WidgetsBindingObserver {
  late Stream<List<HomeExam>> _exams;
  Timer? _midnight;
  String? _loadedKey;
  Future<String>? _subject;
  Future<Map<String, dynamic>>? _stats;
  Future<int>? _count;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setStream();
    _scheduleMidnight();
  }

  void _setStream() {
    final uid = widget.uid;
    _exams = widget.exams ?? FirebaseFirestore.instance
        .collection('users').doc(uid).collection('exams').snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['examDate'];
          DateTime? localDate;
          if (date is Timestamp) {
            try { localDate = date.toDate().toLocal(); } catch (_) { /* Invalid date. */ }
          }
          return HomeExam(id: doc.id, title: data['title']?.toString() ?? '시험 제목 없음',
            date: localDate,
            semesterCode: data['semesterCode'] is String ? data['semesterCode'] as String : null,
            subjectId: data['subjectId'] is String ? data['subjectId'] as String : null);
        }).toList());
  }

  @override
  void didUpdateWidget(covariant ExamStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.exams != widget.exams) {
      _loadedKey = null;
      _setStream();
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      if (!mounted) return;
      refresh();
      _scheduleMidnight();
    });
  }

  void refresh() {
    if (!mounted) return;
    setState(() => _loadedKey = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _loadDetails(HomeExam exam) {
    final semester = exam.semesterCode;
    final subject = exam.subjectId;
    final key = '${widget.uid}/${exam.id}/$semester/$subject';
    if (_loadedKey == key) return;
    _loadedKey = key;
    if (semester == null || semester.trim().isEmpty || semester.contains('/') ||
        subject == null || subject.trim().isEmpty || subject.contains('/')) {
      _subject = null;
      _stats = null;
      _count = null;
      return;
    }
    _subject = widget.subjectLoader?.call(semester, subject) ??
        FirebaseFirestore.instance.collection('users').doc(widget.uid)
            .collection('semesters').doc(semester).collection('subjects').doc(subject)
            .get().then((doc) {
              final name = doc.data()?['name'];
              if (name is! String || name.trim().isEmpty) return '과목 정보 없음';
              return name;
            });
    _stats = widget.statsLoader?.call(semester, subject) ??
        StudyStorage.getSubjectWeakQuestionStats(semesterCode: semester, subjectId: subject);
    _count = widget.countLoader?.call(semester, subject) ??
        StudyStorage.getRecommendedReviewQuestionCount(semesterCode: semester, subjectId: subject);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('시험 대비 현황', style: TextStyle(fontSize: 19,
            fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 12),
          StreamBuilder<List<HomeExam>>(
            key: ValueKey(widget.uid),
            stream: _exams,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                _loadedKey = null;
                return const Text('시험 일정을 불러오지 못했습니다.');
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final exam = nearestHomeExam(snapshot.data!, DateTime.now());
              if (exam == null) {
                _loadedKey = null;
                return const Text('예정된 시험이 없습니다.');
              }
              _loadDetails(exam);
              final date = exam.date!;
              final days = daysUntilExam(date)!;
              final dateText = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(exam.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('시험 날짜: $dateText · ${examDDayText(days)}',
                  style: const TextStyle(color: _lavender)),
                if (_subject == null) const Text('과목 정보 없음') else
                  FutureBuilder<String>(key: ObjectKey(_subject), future: _subject,
                    builder: (context, s) => Text('과목: ${s.hasError ? '과목 조회 실패' : s.data ?? '조회 중...'}')),
                if (_stats == null) const Text('취약 문제 통계를 확인할 수 없습니다.') else
                  FutureBuilder<Map<String, dynamic>>(key: ObjectKey(_stats), future: _stats,
                    builder: (context, s) {
                      if (s.hasError) return const Text('취약 문제 통계를 불러오지 못했습니다.');
                      if (!s.hasData) return const Text('취약 문제 분석 중...');
                      final rate = s.data!['resolutionRate'] as num;
                      return Text('남은 취약 문제: ${s.data!['remainingWeakCount']}개\n취약 문제 해소율: ${rate.toStringAsFixed(1)}%');
                    }),
                if (_count == null) const Text('추천 문제 수를 확인할 수 없습니다.') else
                  FutureBuilder<int>(key: ObjectKey(_count), future: _count,
                    builder: (context, s) {
                      if (s.hasError) return const Text('추천 문제를 불러오지 못했습니다.');
                      if (!s.hasData) return const Text('추천 문제를 불러오는 중...');
                      final count = StudyStorage.calculateTodayRecommendedCount(
                        availableQuestionCount: s.data!, daysUntilExam: days);
                      return Text('오늘의 추천 복습: $count문제');
                    }),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// Pass your existing PDF upload widget through [uploadScreenBuilder].
class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({super.key, required this.uploadScreenBuilder,
    required this.userId, this.profileName, this.profile = const {}});

  final WidgetBuilder uploadScreenBuilder;
  final String userId;
  final String? profileName;
  final Map<String, dynamic> profile;

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  final _examCardKey = GlobalKey<ExamStatusCardState>();
  late final Stream<User?> _authChanges = FirebaseAuth.instance.authStateChanges();
  int _tab = 0;
  final _random = Random();
  final _messages = const [
    '오늘도 효율적으로 공부해봐요!',
    '오늘은 무엇을 공부해볼까요?',
    '작은 성취가 큰 변화를 만들어요.',
    '오늘의 학습 목표를 달성해봐요!',
    '꾸준한 공부가 실력이 됩니다.',
  ];
  late final String _message = _messages[_random.nextInt(_messages.length)];

  void _openUpload() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: widget.uploadScreenBuilder,
    )).then((_) => _refreshExamCard());
  }

  void _refreshExamCard() {
    if (mounted) _examCardKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: const Color(0xFFF9F9FF),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF9F9FF), foregroundColor: _ink),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Study AI',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          elevation: 0,
        ),
        body: _tab == 0
          ? _home()
          : _tab == 1
              ? const StudyHistoryScreen()
              : _myPage(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE9E4FF),
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '학습 기록'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: '내 정보'),
          ],
        ),
      ),
    );
  }
  Widget _myPage() {
    final isCurrentUser = FirebaseAuth.instance.currentUser?.uid == widget.userId;
    String profileValue(String key) {
      final value = isCurrentUser ? widget.profile[key] : null;
      return value is String && value.trim().isNotEmpty ? value.trim() : '정보 없음';
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),

        const CircleAvatar(
          radius: 38,
          backgroundColor: Color(0xFFE9E4FF),
          child: Icon(
            Icons.person,
            size: 42,
            color: _lavender,
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          '내 정보',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: _ink,
          ),
        ),

        const SizedBox(height: 12),

        for (final entry in [('학교', 'school'), ('학과', 'major'), ('학년', 'grade')])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${entry.$1}: ${profileValue(entry.$2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF66708F))),
          ),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: !isCurrentUser ? null : () => Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => ProfileSetupScreen(
              editUserId: widget.userId, initialProfile: widget.profile,
            )),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('수정하기'),
          style: ElevatedButton.styleFrom(foregroundColor: _lavender),
        ),

        const SizedBox(height: 40),

        TextButton.icon(
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('로그아웃'),
                content: const Text('정말 로그아웃하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, true),
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            );

            if (shouldLogout != true || !mounted) return;

            try {
              await FirebaseAuth.instance.signOut();
              // main.dart에서 로그인 상태를 감지하여
              // 로그인 화면으로 자동 전환합니다.
            } catch (e) {
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('로그아웃 실패: $e')),
              );
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('로그아웃'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF77809B),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE5EFFF), Color(0xFFECE4FF)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              FirebaseAuth.instance.currentUser?.uid == widget.userId &&
                      (widget.profileName?.trim().isNotEmpty ?? false)
                  ? '${widget.profileName!.trim()}님, 반갑습니다! 👋'
                  : '반갑습니다! 👋',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: _ink),
            ),
            const SizedBox(height: 10),
            Text(_message, style: const TextStyle(fontSize: 15, color: Color(0xFF58628A))),
          ]),
        ),
        const SizedBox(height: 22),
        StreamBuilder<User?>(
          stream: _authChanges,
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user == null || FirebaseAuth.instance.currentUser?.uid != user.uid) {
              return const SizedBox.shrink();
            }
            return ExamStatusCard(
              key: _examCardKey,
              uid: user.uid,
            );
          },
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.13,
          children: [
            _feature('강의자료 업로드', 'PDF 파일을 등록해요', Icons.upload_file, const Color(0xFFF1E9FF), _openUpload),
            _feature('학습 기록', '공부한 내용을 확인해요', Icons.auto_stories_outlined, const Color(0xFFE6F1FF), () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudyHistoryScreen(),
                ),
              ).then((_) => _refreshExamCard());
            }),
            _feature('복습하기', '배운 내용을 복습해요', Icons.refresh_rounded, const Color(0xFFFFF1E4), () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReviewSelectionScreen(),
                ),
              ).then((_) => _refreshExamCard());
            },),
            _feature(
              '시험 공부 대비하기',
              '시험을 준비해요',
              Icons.fact_check_outlined,
              const Color(0xFFE6F7F3),
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ExamManagementScreen(),
                  ),
                ).then((_) => _refreshExamCard());
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: const Icon(
              Icons.menu_book_rounded,
              color: _lavender,
              size: 30,
            ),
            title: const Text(
              '수강 과목 관리',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
            subtitle: const Text(
              '학기별 수강 과목을 등록하고 관리해요',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubjectManagementScreen(),
                ),
              ).then((_) => _refreshExamCard());
            },
          ),
        
        ),
        const SizedBox(height: 12),

        Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: const Icon(
              Icons.bar_chart_rounded,
              color: _lavender,
              size: 30,
            ),
            title: const Text(
              '학습 성취도 분석',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
            subtitle: const Text(
              '정답률과 취약 문제를 확인해요',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const StudyAnalysisScreen(),
                ),
              ).then((_) => _refreshExamCard());
            },
          ),
        ),

        const SizedBox(height: 26),
        const Text('최근 학습 자료', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _ink)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: const Column(children: [
            Icon(Icons.folder_open_outlined, size: 35, color: _lavender),
            SizedBox(height: 10),
            Text('아직 표시할 학습 자료가 없습니다.', style: TextStyle(color: Color(0xFF77809B))),
            SizedBox(height: 5),
            Text('강의자료를 업로드하면 이곳에서 확인할 수 있어요.', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9299AE))),
          ]),
        ),
      ],
    );
  }

  Widget _feature(String title, String subtitle, IconData icon, Color background, VoidCallback onTap) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _lavender, size: 30),
            const Spacer(),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _ink)),
            const SizedBox(height: 5),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF66708F))),
          ]),
        ),
      ),
    );
  }
}
