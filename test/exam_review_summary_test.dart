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
    expect(find.text('맞춤 복습 설정'), findsOneWidget);
    await tester.tap(find.text('기존 추천 복습 시작'));
    await tester.pumpAndSettle();
    expect(started, 12);
  });

  testWidgets('설정에서 난이도별 후보와 개수 부족을 표시한다', (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReviewSettingsDialog(
      initialCount: 0,
      countForDifficulty: (difficulty) async {
        requested.add(difficulty);
        return {'all': 4, 'easy': 2, 'medium': 1, 'hard': 0}[difficulty]!;
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('1개'), findsOneWidget);
    expect(find.text('추천 가능: 4문제'), findsOneWidget);
    for (final entry in [('쉬움', '추천 가능: 2문제'),
        ('보통', '추천 가능: 1문제'), ('어려움', '선택한 난이도에 복습 가능한 문제가 없습니다.'),
        ('전체', '추천 가능: 4문제')]) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1).last);
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
    }
    expect(requested, ['all', 'easy', 'medium', 'hard', 'all']);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('1개'), findsWidgets);
    await tester.scrollUntilVisible(find.text('20개'), 200,
      scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('20개').last);
    await tester.pumpAndSettle();
    expect(find.text('추천 가능: 4문제 · 요청한 20문제보다 부족합니다.'), findsOneWidget);
  });

  testWidgets('늦게 완료된 이전 조회를 무시하고 로딩과 오류를 표시한다', (tester) async {
    final old = Completer<int>();
    final current = Completer<int>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReviewSettingsDialog(
      initialCount: 30,
      countForDifficulty: (difficulty) => difficulty == 'all' ? old.future : current.future,
    ))));
    await tester.pump();
    expect(find.text('20개'), findsOneWidget);
    expect(find.text('추천 가능 문제를 확인하는 중...'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('쉬움').last);
    await tester.pump();
    old.complete(99);
    await tester.pump();
    expect(find.text('추천 가능: 99문제'), findsNothing);
    expect(find.text('추천 가능 문제를 확인하는 중...'), findsOneWidget);
    current.completeError(Exception('조회 실패'));
    await tester.pumpAndSettle();
    expect(find.text('추천 가능 문제 수를 불러오지 못했습니다.'), findsOneWidget);
  });

  testWidgets('시작 시 다시 조회한 부족 문제를 확인하고 중복 시작을 막는다', (tester) async {
    final fetch = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    List<Map<String, dynamic>>? started;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamReviewSummary(
      weakStats: Future.value(stats), availableCount: Future.value(15), daysUntilExam: 1,
      countForDifficulty: (_) async => 15,
      questionsForSettings: (difficulty, count) {
        expect(difficulty, 'all');
        expect(count, 10);
        calls++;
        return fetch.future;
      },
      onStart: (_) async {}, onStartCustom: (questions) async { started = questions; },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천 복습 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('맞춤 복습 시작'));
    await tester.pump();
    expect(find.text('문제 확인 중...'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '문제 확인 중...')).onPressed, isNull);
    expect(calls, 1);
    fetch.complete(List.generate(8, (i) => {'question': 'Q$i',
      'questionId': 'id$i', 'noteId': 'note', 'concept': '핵심',
      'subConcept': '세부', 'difficulty': 'easy'}));
    await tester.pumpAndSettle();
    expect(find.text('요청한 10문제 중 현재 8문제를 풀 수 있습니다. 이 문제들로 시작할까요?'), findsOneWidget);
    expect(started, isNull);
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(started!.length, 8);
    expect(started!.first['questionId'], 'id0');
    expect(started!.first['noteId'], 'note');
    expect(started!.first['concept'], '핵심');
    expect(started!.first['subConcept'], '세부');
    expect(started!.first['difficulty'], 'easy');
  });

  testWidgets('시작 직전 후보가 없어지면 복습하지 않고 안내한다', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReviewSettingsDialog(
      initialCount: 2, countForDifficulty: (_) async => calls == 0 ? 2 : 0,
      questionsForSettings: (_, _) async { calls++; return []; },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('맞춤 복습 시작'));
    await tester.pumpAndSettle();
    expect(find.text('복습 가능한 문제가 없습니다. 조건을 변경해 주세요.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '맞춤 복습 시작')).onPressed, isNull);
  });

  testWidgets('선택한 난이도와 요청 개수를 실제 조회에 전달한다', (tester) async {
    String? selectedDifficulty;
    int? selectedCount;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamReviewSummary(
      weakStats: Future.value(stats), availableCount: Future.value(10), daysUntilExam: 2,
      countForDifficulty: (_) async => 10,
      questionsForSettings: (difficulty, count) async {
        selectedDifficulty = difficulty;
        selectedCount = count;
        return List.generate(count, (i) => {'question': 'Q$i'});
      },
      onStart: (_) async {}, onStartCustom: (_) async {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천 복습 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('쉬움').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('맞춤 복습 시작'));
    await tester.pumpAndSettle();
    expect(selectedDifficulty, 'easy');
    expect(selectedCount, 5);
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
