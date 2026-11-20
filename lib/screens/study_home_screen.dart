import 'dart:math';
import 'package:flutter/material.dart';
import 'study_history_screen.dart';
import 'wrong_answer_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'subject_management_screen.dart';
import 'study_analysis_screen.dart';
import 'exam_management_screen.dart';

const _lavender = Color(0xFF8576D8);
const _ink = Color(0xFF242B50);

/// Pass your existing PDF upload widget through [uploadScreenBuilder].
class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({super.key, required this.uploadScreenBuilder, this.userName = '00'});

  final WidgetBuilder uploadScreenBuilder;
  final String userName;

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
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
    ));
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
    final user = FirebaseAuth.instance.currentUser;

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

        Text(
          user?.email ?? '이메일 정보 없음',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF66708F),
          ),
        ),

        const SizedBox(height: 40),

        OutlinedButton.icon(
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
          style: OutlinedButton.styleFrom(
            foregroundColor: _lavender,
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
            Text('${widget.userName}님, 반갑습니다! 👋',
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: _ink)),
            const SizedBox(height: 10),
            Text(_message, style: const TextStyle(fontSize: 15, color: Color(0xFF58628A))),
          ]),
        ),
        const SizedBox(height: 22),
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
              );
            }),
            _feature('복습하기', '배운 내용을 복습해요', Icons.refresh_rounded, const Color(0xFFFFF1E4), () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WrongAnswerScreen(),
                ),
              );
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
                );
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
              );
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
              );
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
