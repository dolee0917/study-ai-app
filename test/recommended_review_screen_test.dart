import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/screens/recommended_review_screen.dart';
import 'package:study_ai_app/screens/wrong_answer_retry_screen.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  final originalUser = StudyStorage.currentUserId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'test-user';
  });
  tearDown(() => StudyStorage.currentUserId = originalUser);

  Future<void> startReview(WidgetTester tester, int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_notes', jsonEncode([
      {
        'id': 'session', 'fileName': 'book.pdf',
        'semesterCode': '2026-1', 'subjectId': 'math',
        'questions': [
          for (var i = 0; i < count; i++)
            {'type': 'multiple_choice', 'question': 'Q$i',
              'options': ['A', 'B'], 'answer': 'A'},
        ],
      },
    ]));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => RecommendedReviewScreen(
            semesterCode: '2026-1', subjectId: 'math', count: count),
        )),
        child: const Text('시작 화면'),
      ));
    })));
    await tester.tap(find.text('시작 화면'));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, bool correct, {required bool last}) async {
    await tester.tap(find.text(correct ? 'A' : 'B'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 추천 복습 완료!'), findsNothing);
    final next = find.text(last ? '복습 완료' : '다음 문제');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }

  for (final scenario in [
    (answers: [true, true, true, false, false], correct: 3, accuracy: '60.0'),
    (answers: [true, true, true, true, true], correct: 5, accuracy: '100.0'),
    (answers: [false, false, false, false, false], correct: 0, accuracy: '0.0'),
  ]) {
    testWidgets('추천 복습 결과 ${scenario.accuracy}%', (tester) async {
      await startReview(tester, 5);
      for (var i = 0; i < scenario.answers.length; i++) {
        await answer(tester, scenario.answers[i], last: i == 4);
      }
      expect(find.text('오늘의 추천 복습 완료!'), findsOneWidget);
      expect(find.text('총 문제 수: 5개'), findsOneWidget);
      expect(find.text('정답 수: ${scenario.correct}개'), findsOneWidget);
      expect(find.text('오답 수: ${5 - scenario.correct}개'), findsOneWidget);
      expect(find.text('정답률: ${scenario.accuracy}%'), findsOneWidget);
      await tester.tap(find.text('돌아가기'));
      await tester.pumpAndSettle();
      expect(find.text('시작 화면'), findsOneWidget);
    });
  }

  testWidgets('저장 실패는 완료되지 않으며 재시도할 수 있다', (tester) async {
    await startReview(tester, 1);
    StudyStorage.currentUserId = () => null;
    await tester.tap(find.text('A'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    expect(find.text('재풀이 결과를 저장하지 못했습니다.'), findsOneWidget);
    expect(find.text('복습 완료'), findsNothing);
    expect(find.text('오늘의 추천 복습 완료!'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quiz_retry_results'), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    StudyStorage.currentUserId = () => 'test-user';
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('복습 완료'));
    await tester.tap(find.text('복습 완료'));
    await tester.pumpAndSettle();
    expect(find.text('정답 수: 1개'), findsOneWidget);
  });

  testWidgets('동일 문제의 중복 결과는 집계되지 않는다', (tester) async {
    await startReview(tester, 1);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    final screen = tester.widget<WrongAnswerRetryScreen>(find.byType(WrongAnswerRetryScreen));
    screen.onAnswerSaved!(false);
    await tester.ensureVisible(find.text('복습 완료'));
    await tester.tap(find.text('복습 완료'));
    await tester.pumpAndSettle();
    expect(find.text('총 문제 수: 1개'), findsOneWidget);
    expect(find.text('정답 수: 1개'), findsOneWidget);
  });

  testWidgets('문제 풀이 중 뒤로 가면 결과 없이 이전 화면으로 돌아간다', (tester) async {
    await startReview(tester, 2);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('시작 화면'), findsOneWidget);
    expect(find.text('오늘의 추천 복습 완료!'), findsNothing);
  });

  testWidgets('추천 문제가 없으면 기존 안내를 표시한다', (tester) async {
    await startReview(tester, 0);
    expect(find.text('복습 가능한 추천 문제가 없습니다.'), findsOneWidget);
  });

  testWidgets('사전 조회한 맞춤 문제를 사용하고 풀이 결과로 취약 상태를 해제한다', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_notes', jsonEncode([{
      'id': 'note', 'fileName': 'book.pdf', 'semesterCode': '2026-1', 'subjectId': 'math',
      'questions': [{'type': 'multiple_choice', 'question': 'Q', 'options': ['A', 'B'],
        'answer': 'A', 'difficulty': 'easy'}],
    }]));
    await StudyStorage.saveRetryResult(question: 'Q', userAnswer: 'B', correctAnswer: 'A',
      isCorrect: false, fileName: 'book.pdf', semesterCode: '2026-1', subjectId: 'math');
    await StudyStorage.saveRetryResult(question: 'Q', userAnswer: 'A', correctAnswer: 'A',
      isCorrect: true, fileName: 'book.pdf', semesterCode: '2026-1', subjectId: 'math');
    final questions = await StudyStorage.getRecommendedReviewQuestions(
      semesterCode: '2026-1', subjectId: 'math', difficulty: 'easy', limit: 1);
    await prefs.setString('study_notes', '[]');
    await tester.pumpWidget(MaterialApp(home: RecommendedReviewScreen(
      semesterCode: '2026-1', subjectId: 'math', count: 1, questions: questions)));
    await tester.pumpAndSettle();
    expect(find.text('Q'), findsOneWidget);
    await answer(tester, true, last: true);
    expect(await StudyStorage.getQuestionLearningStatus(question: 'Q', fileName: 'book.pdf',
      semesterCode: '2026-1', subjectId: 'math'), '해제');
    final results = jsonDecode(prefs.getString('quiz_retry_results')!) as List;
    expect(results.first['reviewType'], 'recommended_review');
  });

  testWidgets('오답 재풀이는 기존 제목과 안내를 표시한다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WrongAnswerRetryScreen(question: {
        'question': '문제',
        'options': ['A', 'B'],
        'correctAnswer': 'A',
      }),
    ));

    expect(find.text('오답 다시 풀기'), findsOneWidget);
    expect(find.text('다시 도전해보세요!'), findsOneWidget);
    expect(find.text('오늘의 추천 복습'), findsNothing);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final results = jsonDecode(prefs.getString('quiz_retry_results')!) as List;
    expect(results.single['reviewType'], 'wrong_answer_retry');
  });

  testWidgets('기존 재풀이 완료 콜백이 유지된다', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: WrongAnswerRetryScreen(
      question: const {'question': 'Q', 'options': ['A'], 'correctAnswer': 'A'},
      currentNumber: 1,
      totalCount: 1,
      onCompleted: () => completed = true,
    )));
    await tester.tap(find.text('A'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('복습 완료'));
    await tester.tap(find.text('복습 완료'));
    expect(completed, isTrue);
  });

  testWidgets('추천 복습의 문구와 진행 및 결과 저장이 유지된다', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_notes', jsonEncode([
      {
        'id': 'note',
        'fileName': 'book.pdf',
        'semesterCode': '2026-1',
        'subjectId': 'math',
        'questions': [
          for (final text in ['문제 1', '문제 2'])
            {
              'type': 'multiple_choice',
              'question': text,
              'options': ['A', 'B'],
              'answer': 'A',
              'explanation': '해설',
            },
        ],
      },
    ]));
    await tester.pumpWidget(const MaterialApp(
      home: RecommendedReviewScreen(
        semesterCode: '2026-1', subjectId: 'math', count: 2),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 추천 복습'), findsOneWidget);
    expect(find.text('오늘의 추천 문제를 풀어보세요!'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('정답 확인하기'));
    await tester.pumpAndSettle();
    expect(find.text('정답입니다!'), findsOneWidget);
    expect(find.text('AI 문제 해설'), findsOneWidget);
    final results = jsonDecode(prefs.getString('quiz_retry_results')!) as List;
    expect(results.single['isCorrect'], isTrue);
    expect(results.single['userAnswer'], 'A');
    expect(results.single['reviewType'], 'recommended_review');
    await tester.ensureVisible(find.text('다음 문제'));
    await tester.tap(find.text('다음 문제'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('오늘의 추천 복습'), findsOneWidget);
  });
}
