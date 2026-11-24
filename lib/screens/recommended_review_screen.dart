import 'package:flutter/material.dart';

import '../services/study_storage.dart';
import 'wrong_answer_retry_screen.dart';

class RecommendedReviewScreen extends StatefulWidget {
  const RecommendedReviewScreen({
    super.key,
    required this.semesterCode,
    required this.subjectId,
    required this.count,
    this.questions,
  });

  final String semesterCode;
  final String subjectId;
  final int count;
  final List<Map<String, dynamic>>? questions;

  @override
  State<RecommendedReviewScreen> createState() => _RecommendedReviewScreenState();
}

class _RecommendedReviewScreenState extends State<RecommendedReviewScreen> {
  late final Future<List<Map<String, dynamic>>> _questions;
  late final String? _sessionUserId;
  int _index = 0;
  final Map<int, bool> _results = {};
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _sessionUserId = StudyStorage.currentUserId();
    _questions = widget.questions != null ? Future.value(widget.questions!) : StudyStorage.getRecommendedReviewQuestions(
      semesterCode: widget.semesterCode,
      subjectId: widget.subjectId,
      limit: widget.count,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _questions,
      builder: (context, snapshot) {
        if (_sessionUserId == null || StudyStorage.currentUserId() != _sessionUserId) {
          return Scaffold(
            appBar: AppBar(title: const Text('추천 복습')),
            body: const Center(child: Text('로그인 사용자가 변경되었습니다. 복습을 다시 시작해주세요.')),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('추천 복습')),
            body: const Center(child: Text('추천 문제를 불러오지 못했습니다.')),
          );
        }
        final questions = snapshot.data ?? [];
        if (questions.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('추천 복습')),
            body: const Center(child: Text('복습 가능한 추천 문제가 없습니다.')),
          );
        }
        if (_completed) {
          final correct = _results.values.where((result) => result).length;
          final total = _results.length;
          final accuracy = correct / total * 100;
          return Scaffold(
            appBar: AppBar(title: const Text('오늘의 추천 복습 완료!')),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('총 문제 수: $total개', style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 12),
                      Text('정답 수: $correct개', style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 12),
                      Text('오답 수: ${total - correct}개', style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 12),
                      Text(
                        '정답률: ${accuracy.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold,
                          color: Color(0xFF6F63B5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('돌아가기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final currentIndex = _index;
        return WrongAnswerRetryScreen(
          key: ValueKey(_index),
          question: questions[_index],
          isRecommendedReview: true,
          currentNumber: _index + 1,
          totalCount: questions.length,
          onAnswerSaved: (result) => _results.putIfAbsent(currentIndex, () => result),
          onCompleted: () {
            if (StudyStorage.currentUserId() != _sessionUserId) {
              setState(() {});
              return;
            }
            if (_completed || _index != currentIndex || !_results.containsKey(currentIndex)) return;
            if (_index + 1 == questions.length) {
              setState(() => _completed = true);
            } else {
              setState(() => _index++);
            }
          },
        );
      },
    );
  }
}
