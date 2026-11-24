import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/study_storage.dart';

class StudyAnalysisScreen extends StatefulWidget {
  const StudyAnalysisScreen({super.key, this.registeredSubjectsLoader});

  // Allows the filter choices to be supplied without Firebase in widget tests.
  final Future<List<Map<String, String>>> Function(Set<String>)? registeredSubjectsLoader;

  @override
  State<StudyAnalysisScreen> createState() => _StudyAnalysisScreenState();
}

class _StudyAnalysisScreenState extends State<StudyAnalysisScreen> {
  static const _lavender = Color(0xFF8576D8);
  static const _ink = Color(0xFF242B50);
  static const _accent = Color(0xFF65558F);
  static const _border = Color(0xFFE6E0EC);
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<Map<String, dynamic>>> _subjectsFuture;
  late Future<List<Map<String, dynamic>>> _questionsFuture;
  final _names = <String, Future<String>>{};
  String? _semester;
  String? _subjectKey;
  List<Map<String, String>> _options = [];
  Set<String> _semesters = {};
  bool _optionsLoading = true;
  bool _optionsError = false;

  String _key(String semester, String subject) => jsonEncode([semester, subject]);
  List<String> get _selectedPair => _subjectKey == null
      ? <String>[] : (jsonDecode(_subjectKey!) as List).cast<String>();
  String? get _effectiveSemester => _subjectKey == null ? _semester : _selectedPair[0];
  String? get _effectiveSubject => _subjectKey == null ? null : _selectedPair[1];

  bool _matches(Map<String, dynamic> item) =>
      (_effectiveSemester == null || item['semesterCode'] == _effectiveSemester) &&
      (_effectiveSubject == null || item['subjectId'] == _effectiveSubject);

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    _loadOptions();
  }

  Future<Map<String, dynamic>> _loadStats() async {
    _questionsFuture = StudyStorage.getQuestionAnalysis();
    _questionsFuture.ignore();
    _subjectsFuture = StudyStorage.getSubjectAccuracyStats();
    _subjectsFuture.ignore();
    return StudyStorage.getMultipleChoiceStats(
      semesterCode: _effectiveSemester, subjectId: _effectiveSubject);
  }

  void _refreshStats() {
    _statsFuture = _loadStats();
  }

  Future<void> _loadOptions() async {
    var failed = false;
    final pairs = <String, Map<String, String>>{};
    final semesters = <String>{};
    try {
      final records = <Map<String, dynamic>>[
        ...await StudyStorage.getSubjectAccuracyStats(),
        ...await StudyStorage.loadQuizResults(),
      ];
      for (final record in records) {
        final semester = record['semesterCode']?.toString() ?? '';
        final subject = record['subjectId']?.toString() ?? '';
        if (semester.isEmpty) continue;
        semesters.add(semester);
        if (subject.isNotEmpty) {
          pairs[_key(semester, subject)] = {'semesterCode': semester, 'subjectId': subject};
        }
      }
    } catch (_) {
      failed = true;
    }
    try {
      final years = <String>{...semesters};
      final year = DateTime.now().year;
      for (var i = 0; i < 6; i++) {
        years.add('${year - i}-1');
        years.add('${year - i}-2');
      }
      final registered = await (widget.registeredSubjectsLoader?.call(years) ?? _registeredSubjects(years));
      for (final item in registered) {
        final semester = item['semesterCode'] ?? '';
        final subject = item['subjectId'] ?? '';
        if (semester.isEmpty || subject.isEmpty) continue;
        semesters.add(semester);
        pairs[_key(semester, subject)] = item;
        final name = item['name'];
        if (name != null && name.trim().isNotEmpty) {
          _names['$semester/$subject'] = Future.value(name);
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _semesters = semesters;
      _options = pairs.values.toList();
      _optionsLoading = false;
      _optionsError = failed;
    });
  }

  Future<List<Map<String, String>>> _registeredSubjects(Set<String> semesters) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final root = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('semesters');
    final results = await Future.wait(semesters.map((semester) async {
      final snapshot = await root.doc(semester).collection('subjects').get();
      return snapshot.docs.map((doc) => {
        'semesterCode': semester, 'subjectId': doc.id,
        'name': doc.data()['name']?.toString() ?? '',
      }).toList();
    }));
    return results.expand((items) => items).toList();
  }

  Future<String> _getSubjectName({required String subjectId, required String semesterCode}) async {
    if (subjectId.isEmpty || semesterCode.isEmpty) return '미지정 과목';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '알 수 없는 과목';
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid)
        .collection('semesters').doc(semesterCode).collection('subjects').doc(subjectId).get();
    if (!doc.exists) return '삭제되었거나 없는 과목';
    final name = doc.data()?['name']?.toString().trim();
    return name == null || name.isEmpty ? '이름 없는 과목' : name;
  }

  BoxDecoration _card({Color color = Colors.white}) => BoxDecoration(
    color: color, borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _border),
  );

  Widget _heading(String title) => Text(title, style: const TextStyle(
    color: _ink, fontSize: 19, fontWeight: FontWeight.bold));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FC),
      appBar: AppBar(title: const Text('학습 성취도 분석')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildFilters(),
        ),
        if (_optionsError) const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('일부 학기 또는 과목을 불러오지 못했습니다. 학습 기록의 선택지는 이용할 수 있습니다.',
            style: TextStyle(color: _accent, fontSize: 12)),
        ),
        Expanded(child: FutureBuilder<Map<String, dynamic>>(
          key: ObjectKey(_statsFuture),
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('학습 분석 실패: ${snapshot.error}');
            return const Center(child: Text('학습 데이터를 불러오지 못했습니다.'));
          }
          final stats = snapshot.data;
          if (stats == null || stats['hasData'] != true) {
            if (_semester != null || _subjectKey != null) {
              return const Center(child: Text('선택한 범위에 학습 기록이 없습니다.'));
            }
            return const Center(child: Text(
              '아직 분석할 객관식 학습 기록이 없습니다.\n계정 정보가 없는 과거 기록은 분석에서 제외됩니다.',
              textAlign: TextAlign.center));
          }
          final accuracy = stats['accuracy'] as double;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [
              _heading('전체 학습 성취도'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _card(color: const Color(0xFFEDE8F8)),
                child: Row(children: [
                  SizedBox(
                    width: 118, height: 118,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(child: CircularProgressIndicator(
                        key: const ValueKey('overall_accuracy_chart'),
                        value: (accuracy / 100).clamp(0.0, 1.0),
                        strokeWidth: 10, color: _lavender,
                        backgroundColor: const Color(0xFFDAD2EC),
                      )),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        FittedBox(child: Text('${accuracy.toStringAsFixed(1)}%',
                          style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.bold))),
                        const Text('객관식 정답률', style: TextStyle(color: _accent, fontSize: 11)),
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: Column(children: [
                    _statRow('전체 풀이', stats['totalCount'] as int),
                    const SizedBox(height: 12),
                    _statRow('정답', stats['correctCount'] as int),
                    const SizedBox(height: 12),
                    _statRow('오답', stats['wrongCount'] as int),
                  ])),
                ]),
              ),
              const SizedBox(height: 24),
              _heading('과목별 성취도'),
              const SizedBox(height: 12),
              _buildSubjectStats(),
              const SizedBox(height: 24),
              _heading('취약 문제 현황'),
              const SizedBox(height: 12),
              _buildQuestionSummary(),
              const SizedBox(height: 16),
              const Text('객관식 풀이와 재풀이를 각각 집계합니다. 주관식은 자동 채점하지 않습니다.\n계정 정보가 없는 과거 기록은 보존되지만 분석에서 제외됩니다.',
                style: TextStyle(color: _accent, fontSize: 12)),
            ],
          );
        },
      )),
      ]),
    );
  }

  Widget _buildFilters() {
    final semesters = _semesters.toList()..sort((a, b) => b.compareTo(a));
    final subjects = _options.where((item) =>
        _semester == null || item['semesterCode'] == _semester).toList();
    subjects.sort((a, b) => (a['semesterCode'] ?? '').compareTo(b['semesterCode'] ?? ''));
    return Row(children: [
      Expanded(child: _filterBox(DropdownButton<String>(
        key: const ValueKey('semester_filter'), value: _semester ?? '',
        hint: const Text('전체 학기', overflow: TextOverflow.ellipsis),
        isExpanded: true, underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem<String>(value: '', child: Text('전체 학기')),
          for (final semester in semesters)
            DropdownMenuItem(value: semester, child: Text(_semesterLabel(semester), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _optionsLoading ? null : (value) => setState(() {
          _semester = value == '' ? null : value;
          _subjectKey = null;
          _refreshStats();
        }),
      ))),
      const SizedBox(width: 12),
      Expanded(child: _filterBox(DropdownButton<String>(
        key: const ValueKey('subject_filter'), value: _subjectKey ?? '',
        hint: const Text('전체 과목', overflow: TextOverflow.ellipsis),
        isExpanded: true, underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem<String>(value: '', child: Text('전체 과목')),
          for (final subject in subjects)
            DropdownMenuItem(
              value: _key(subject['semesterCode']!, subject['subjectId']!),
              child: _subjectOption(subject),
            ),
        ],
        onChanged: _optionsLoading ? null : (value) => setState(() {
          _subjectKey = value == '' ? null : value;
          _refreshStats();
        }),
      ))),
    ]);
  }

  Widget _filterBox(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    decoration: _card(), child: child,
  );

  Widget _subjectOption(Map<String, String> subject) {
    final semester = subject['semesterCode']!;
    final id = subject['subjectId']!;
    return FutureBuilder<String>(
      future: _names.putIfAbsent('$semester/$id',
        () => _getSubjectName(subjectId: id, semesterCode: semester)),
      builder: (context, snapshot) {
        final name = snapshot.hasError ? '과목 이름을 불러올 수 없습니다'
            : snapshot.data ?? '과목 불러오는 중...';
        return Text(_semester == null ? '$name (${_semesterLabel(semester)})' : name,
          maxLines: 1, overflow: TextOverflow.ellipsis);
      },
    );
  }

  Widget _statRow(String label, int value) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: _ink))),
    Text('$value회', style: const TextStyle(color: _ink, fontWeight: FontWeight.bold)),
  ]);

  Widget _buildSubjectStats() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _subjectsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return const Text('과목별 통계를 불러오지 못했습니다.');
      final subjects = (snapshot.data ?? []).where(_matches).toList();
      if (subjects.isEmpty) return const Text('아직 과목별 학습 기록이 없습니다.');
      return Column(children: subjects.map((subject) {
        final subjectId = subject['subjectId']?.toString() ?? '';
        final semester = subject['semesterCode']?.toString() ?? '';
        final accuracy = subject['accuracy'] as double;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16), decoration: _card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: FutureBuilder<String>(
                future: _names.putIfAbsent('$semester/$subjectId', () => _getSubjectName(subjectId: subjectId, semesterCode: semester)),
                builder: (context, name) => Text(
                  name.hasError ? '과목 이름을 불러올 수 없습니다' : name.data ?? '과목 불러오는 중...',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.bold, fontSize: 16)),
              )),
              const SizedBox(width: 8),
              Text('${accuracy.toStringAsFixed(1)}%', style: const TextStyle(color: _accent, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text(_semesterLabel(semester), style: const TextStyle(color: _accent, fontSize: 12)),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
              value: (accuracy / 100).clamp(0.0, 1.0), minHeight: 7,
              color: _lavender, backgroundColor: const Color(0xFFE8E2F2))),
            const SizedBox(height: 10),
            Text('정답 ${subject['correctCount']}회 · 오답 ${subject['wrongCount']}회 · 전체 ${subject['totalCount']}회',
              style: const TextStyle(color: _accent, fontSize: 12)),
          ]),
        );
      }).toList());
    },
  );

  String _semesterLabel(String code) {
    final match = RegExp(r'^(\d{4})-([12])$').firstMatch(code);
    return match == null ? '학기: $code' : '${match[1]}학년도 ${match[2]}학기';
  }

  Widget _buildQuestionSummary() => Container(
    padding: const EdgeInsets.all(16), decoration: _card(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return const Text('문제 분석을 불러오지 못했습니다.');
          final counts = <String, int>{'복습 필요': 0, '취약': 0, '개선 중': 0, '해제': 0};
          for (final question in (snapshot.data ?? <Map<String, dynamic>>[]).where(_matches)) {
            final status = question['status'];
            if (counts.containsKey(status)) counts[status as String] = counts[status]! + 1;
          }
          final remaining = counts['복습 필요']! + counts['취약']! + counts['개선 중']!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _statusTile('복습 필요', counts['복습 필요']!, const Color(0xFFF7F1E6), const Color(0xFFA67C37))),
              const SizedBox(width: 10),
              Expanded(child: _statusTile('취약', counts['취약']!, const Color(0xFFF9ECEC), const Color(0xFFB85C5C))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _statusTile('개선 중', counts['개선 중']!, const Color(0xFFEFEBF9), const Color(0xFF7563B5))),
              const SizedBox(width: 10),
              Expanded(child: _statusTile('해제', counts['해제']!, const Color(0xFFEAF3ED), const Color(0xFF49876C))),
            ]),
            const SizedBox(height: 16),
            Text('남은 복습 대상: $remaining문제', style: const TextStyle(color: _ink, fontWeight: FontWeight.bold)),
          ]);
        },
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          disabledBackgroundColor: const Color(0xFFF0EBF9),
          disabledForegroundColor: _accent.withValues(alpha: 0.65),
          side: BorderSide.none, padding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(children: [
          Icon(Icons.menu_book_outlined),
          Expanded(child: Text('취약 문제 복습하기 (준비 중)', textAlign: TextAlign.center)),
          Icon(Icons.chevron_right),
        ]),
      )),
    ]),
  );

  Widget _statusTile(String label, int count, Color background, Color foreground) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('$count문제', key: ValueKey('status_$label'),
        style: TextStyle(color: foreground, fontSize: 26, fontWeight: FontWeight.bold)),
    ]),
  );
}
