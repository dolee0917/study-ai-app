import 'package:flutter/material.dart';

import '../services/study_storage.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudyAnalysisScreen extends StatefulWidget {
  const StudyAnalysisScreen({super.key});

  @override
  State<StudyAnalysisScreen> createState() => _StudyAnalysisScreenState();
}

class _StudyAnalysisScreenState extends State<StudyAnalysisScreen> {
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<Map<String, dynamic>>> _subjectsFuture;
  late Future<List<Map<String, dynamic>>> _questionsFuture;
  final _names = <String, Future<String>>{};

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<Map<String, dynamic>> _loadStats() async {
    final data = await Future.wait<dynamic>([
      StudyStorage.getMultipleChoiceStats(),
      StudyStorage.getSubjectAccuracyStats(),
      StudyStorage.getQuestionAnalysis(),
    ]);
    _subjectsFuture = Future.value(data[1] as List<Map<String, dynamic>>);
    _questionsFuture = Future.value(data[2] as List<Map<String, dynamic>>);
    return data[0] as Map<String, dynamic>;
  }

  // Firestore에서 과목 이름 조회
  Future<String> _getSubjectName({
    required String subjectId,
    required String semesterCode,
  }) async {
    if (subjectId.isEmpty || semesterCode.isEmpty) return '미지정 과목';
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return '알 수 없는 과목';
    }

    final subjectDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('semesters')
        .doc(semesterCode)
        .collection('subjects')
        .doc(subjectId)
        .get();

    if (!subjectDoc.exists) {
      return '삭제되었거나 없는 과목';
    }

    return subjectDoc.data()?['name']?.toString() ?? '이름 없는 과목';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학습 성취도 분석')),
      body: FutureBuilder<Map<String, dynamic>>(
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
            return const Center(
              child: Text(
                '아직 분석할 객관식 학습 기록이 없습니다.\n계정 정보가 없는 과거 기록은 분석에서 제외됩니다.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final totalCount = stats['totalCount'] as int;
          final correctCount = stats['correctCount'] as int;
          final wrongCount = stats['wrongCount'] as int;
          final accuracy = stats['accuracy'] as double;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '전체 학습 성취도',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('객관식 정답률'),
                      const SizedBox(height: 8),
                      Text(
                        '${accuracy.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: accuracy / 100,
                        minHeight: 8,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _statRow('전체 풀이', totalCount),
                      const Divider(),
                      _statRow('정답', correctCount),
                      const Divider(),
                      _statRow('오답', wrongCount),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '과목별 학습 성취도',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildSubjectStats(),
              const SizedBox(height: 28),
              _buildQuestions(),
              const SizedBox(height: 16),
              const Text(
                '객관식 풀이와 재풀이를 각각 집계합니다. 주관식은 자동 채점하지 않습니다.\n계정 정보가 없는 과거 기록은 보존되지만 분석에서 제외됩니다.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statRow(String label, int value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text('$value문제', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSubjectStats() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _subjectsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Text('과목별 통계를 불러오지 못했습니다.');
        }

        final subjects = snapshot.data ?? [];

        if (subjects.isEmpty) {
          return const Text('아직 과목별 학습 기록이 없습니다.');
        }

        return Column(
          children: subjects.map((subject) {
            final subjectId = subject['subjectId']?.toString() ?? '';
            final semesterCode = subject['semesterCode']?.toString() ?? '';

            final accuracy = subject['accuracy'] as double;
            final totalCount = subject['totalCount'] as int;
            final correctCount = subject['correctCount'] as int;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: _names.putIfAbsent(
                        '$semesterCode/$subjectId',
                        () => _getSubjectName(
                          subjectId: subjectId,
                          semesterCode: semesterCode,
                        ),
                      ),
                      builder: (context, nameSnapshot) {
                        if (nameSnapshot.hasError) {
                          debugPrint('과목 조회 실패: ${nameSnapshot.error}');
                          return const Text('과목 이름 조회 실패');
                        }

                        return Text(
                          nameSnapshot.data ?? '과목 불러오는 중...',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('학기: $semesterCode'),
                    const SizedBox(height: 8),
                    Text('정답률 ${accuracy.toStringAsFixed(1)}%'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: accuracy / 100,
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '정답 $correctCount / 오답 ${subject['wrongCount']} / 전체 $totalCount',
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildQuestions() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _questionsFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        debugPrint('문제 분석 실패: ${snapshot.error}');
        return const Text('문제 분석을 불러오지 못했습니다.');
      }
      if (!snapshot.hasData) return const CircularProgressIndicator();
      final questions = snapshot.data!;
      final weak = questions
          .where((q) => q['wrongCount'] >= 1 && q['status'] != '해제')
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '취약 문제 목록',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (weak.isEmpty) const Text('복습이 필요한 문제가 없습니다.'),
          for (final q in weak) _questionCard(q),
          const SizedBox(height: 24),
          const Text(
            '문제별 학습 상태',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final q in questions) _questionCard(q),
        ],
      );
    },
  );

  Widget _questionCard(Map<String, dynamic> q) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q['question']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '학습 상태: ${q['status']}',
            style: const TextStyle(color: Color(0xFF6F63B5)),
          ),
          Text(
            '누적 오답 ${q['wrongCount']}회 · 최근 재풀이 연속 정답 ${q['consecutiveCorrect']}회',
          ),
          Text(
            '학기: ${q['semesterCode'] ?? '미지정'} · 과목: ${q['subjectId'] ?? '미지정'}',
          ),
          Text('학습 자료: ${q['fileName'] ?? '미지정'}'),
        ],
      ),
    ),
  );
}
