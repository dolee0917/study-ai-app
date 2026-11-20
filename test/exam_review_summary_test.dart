import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/screens/exam_management_screen.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  final stats = <String, dynamic>{'remainingWeakCount': 0, 'resolutionRate': 0.0};

  test('전체 후보 기준 D-day 계산과 최대 10개 제한', () {
    for (final c in [[20, 10, 2], [12, 5, 3], [15, 2, 8],
        [12, 1, 10], [7, 0, 7], [12, -1, 0], [0, 5, 0], [99, 2, 10]]) {
      expect(StudyStorage.calculateTodayRecommendedCount(
        availableQuestionCount: c[0], daysUntilExam: c[1]), c[2]);
    }
  });

  test('후보 수는 실제 추천 목록과 같고 학기·과목을 분리한다', () async {
    SharedPreferences.setMockInitialValues({});
    final previous = StudyStorage.currentUserId;
    StudyStorage.currentUserId = () => 'candidate-count-test';
    addTearDown(() => StudyStorage.currentUserId = previous);
    final q = {'type': 'multiple_choice', 'question': 'Q',
      'options': ['A', 'B'], 'answer': 'A'};
    await StudyStorage.saveNote(noteId: 'one', fileName: 'a.pdf', summaryText: '',
      originalText: '', semesterCode: '2026-1', subjectId: 'math', questions: [q, q]);
    await StudyStorage.saveNote(noteId: 'two', fileName: 'b.pdf', summaryText: '',
      originalText: '', semesterCode: '2026-1', subjectId: 'science', questions: [q]);
    final count = await StudyStorage.getRecommendedReviewQuestionCount(
      semesterCode: '2026-1', subjectId: 'math');
    final questions = await StudyStorage.getRecommendedReviewQuestions(
      semesterCode: '2026-1', subjectId: 'math', limit: 100);
    expect(count, 1);
    expect(count, questions.length);
    expect((await StudyStorage.getSubjectWeakQuestionStats(
      semesterCode: '2026-1', subjectId: 'math'))['remainingWeakCount'], 0);
    expect(await StudyStorage.getRecommendedReviewQuestionCount(
      semesterCode: '2026-2', subjectId: 'math'), 0);
  });

  testWidgets('취약 문제가 없어도 추천 가능 문제로 버튼이 활성화된다', (tester) async {
    int? started;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamReviewSummary(
      weakStats: Future.value(stats), availableCount: Future.value(12), daysUntilExam: 5,
      onStart: (count) async { started = count; },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('남은 취약 문제: 0개'), findsOneWidget);
    expect(find.text('오늘의 추천 복습: 3문제'), findsOneWidget);
    await tester.tap(find.text('추천 복습 시작하기'));
    await tester.pumpAndSettle();
    expect(started, 12);
  });

  testWidgets('후보 없음, 종료 및 잘못된 날짜에서 시작 버튼이 비활성화된다', (tester) async {
    for (final entry in <(int, int?, String)>[
      (0, 5, '복습할 문제가 없습니다.'),
      (5, -1, '종료된 시험입니다.'),
      (5, null, '시험 날짜를 확인할 수 없습니다.'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamReviewSummary(
        weakStats: Future.value(stats), availableCount: Future.value(entry.$1),
        daysUntilExam: entry.$2, onStart: (_) async {},
      ))));
      await tester.pumpAndSettle();
      expect(find.text(entry.$3), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    }
  });

  testWidgets('복습 후 새 통계와 후보를 표시하며 이전 비동기 결과를 무시한다', (tester) async {
    final oldStats = Completer<Map<String, dynamic>>();
    final oldCount = Completer<int>();
    final newStats = Completer<Map<String, dynamic>>();
    final newCount = Completer<int>();
    var generation = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return ExamReviewSummary(
          weakStats: generation == 0 ? oldStats.future : newStats.future,
          availableCount: generation == 0 ? oldCount.future : newCount.future,
          daysUntilExam: 1, onStart: (_) async {},
        );
      },
    ))));
    update(() => generation = 1);
    await tester.pump();
    oldStats.complete({'remainingWeakCount': 9, 'resolutionRate': 0.0});
    oldCount.complete(9);
    await tester.pump();
    expect(find.text('추천 문제를 불러오는 중...'), findsOneWidget);
    expect(find.text('오늘의 추천 복습: 9문제'), findsNothing);
    newStats.complete({'remainingWeakCount': 1, 'resolutionRate': 50.0});
    newCount.complete(2);
    await tester.pumpAndSettle();
    expect(find.text('남은 취약 문제: 1개'), findsOneWidget);
    expect(find.text('취약 문제 해소율: 50.0%'), findsOneWidget);
    expect(find.text('오늘의 추천 복습: 2문제'), findsOneWidget);
  });
}
