import 'package:flutter/material.dart';

import '../services/study_storage.dart';
import 'wrong_answer_retry_screen.dart';

class RecommendedReviewScreen extends StatefulWidget {
  const RecommendedReviewScreen({
    super.key,
    required this.semesterCode,
    required this.subjectId,
    required this.count,
  });

  final String semesterCode;
  final String subjectId;
  final int count;

  @override
  State<RecommendedReviewScreen> createState() => _RecommendedReviewScreenState();
}

class _RecommendedReviewScreenState extends State<RecommendedReviewScreen> {
  late final Future<List<Map<String, dynamic>>> _questions;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _questions = StudyStorage.getRecommendedReviewQuestions(
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
        return WrongAnswerRetryScreen(
          key: ValueKey(_index),
          question: questions[_index],
          currentNumber: _index + 1,
          totalCount: questions.length,
          onCompleted: () {
            if (_index + 1 == questions.length) {
              Navigator.pop(context);
            } else {
              setState(() => _index++);
            }
          },
        );
      },
    );
  }
}
