import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';
import 'package:study_ai_app/screens/study_analysis_screen.dart';

void main() {
  final original = StudyStorage.currentUserId;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'alice';
  });
  tearDown(() => StudyStorage.currentUserId = original);

  Future<void> quiz({
    bool correct = false,
    String subject = 'math',
    String file = 'book.pdf',
    String type = 'multiple_choice',
  }) => StudyStorage.saveQuizResult(
    fileName: file,
    subjectId: subject,
    semesterCode: '2026',
    answers: [
      {'question': 'Q', 'type': type, 'isCorrect': correct},
    ],
    correctCount: correct ? 1 : 0,
  );
  Future<void> retry(bool correct) => StudyStorage.saveRetryResult(
    question: 'Q',
    userAnswer: 'A',
    correctAnswer: 'A',
    isCorrect: correct,
    subjectId: 'math',
    semesterCode: '2026',
    fileName: 'book.pdf',
  );
  Future<String> status() => StudyStorage.getQuestionLearningStatus(
    question: 'Q',
    subjectId: 'math',
    semesterCode: '2026',
    fileName: 'book.pdf',
  );

  test('객관식 반복 풀이와 재풀이만 집계하고 과목별 정답/오답 계산', () async {
    await quiz();
    await quiz(correct: true);
    await quiz(type: 'short_answer');
    await quiz(subject: 'science');
    await retry(true);
    final all = await StudyStorage.getMultipleChoiceStats();
    expect(all['totalCount'], 4);
    expect(all['accuracy'], 50.0);
    final math = (await StudyStorage.getSubjectAccuracyStats()).firstWhere(
      (s) => s['subjectId'] == 'math',
    );
    expect(math['totalCount'], 3);
    expect(math['correctCount'], 2);
    expect(math['wrongCount'], 1);
    expect(math['accuracy'], closeTo(200 / 3, .0001));
  });

  test('상태 우선순위와 연속 두 번 정답 해제 및 재오답 처리', () async {
    expect(await status(), '정상');
    await quiz(correct: true);
    expect(await status(), '정상');
    await quiz();
    expect(await status(), '복습 필요');
    await retry(false);
    expect(await status(), '취약');
    await retry(true);
    expect(await status(), '개선 중');
    await retry(true);
    expect(await status(), '해제');
    await retry(false);
    expect(await status(), '취약');
    expect(
      await StudyStorage.getQuestionWrongCount(
        question: 'Q',
        subjectId: 'math',
        semesterCode: '2026',
        fileName: 'book.pdf',
      ),
      3,
    );
  });

  test('동일 문장도 과목과 파일이 다르면 별도 문제', () async {
    await quiz();
    await quiz();
    await quiz(subject: 'science');
    await quiz(file: 'other.pdf');
    final questions = await StudyStorage.getQuestionAnalysis();
    expect(questions.length, 3);
    expect(questions.where((q) => q['wrongCount'] == 2).length, 1);
  });

  test('일반 퀴즈와 재풀이를 시간순으로 통합하고 일반 퀴즈 재오답을 반영한다', () async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> quizRecord(String id, String date, bool correct) => {
      'id': id, 'userId': 'alice', 'fileName': 'book.pdf',
      'semesterCode': '2026', 'subjectId': 'math', 'createdAt': date,
      'answers': [{'question': 'Q', 'type': 'multiple_choice', 'isCorrect': correct}],
    };
    Map<String, dynamic> retryRecord(String id, String date, bool correct) => {
      'id': id, 'userId': 'alice', 'fileName': 'book.pdf',
      'semesterCode': '2026', 'subjectId': 'math', 'createdAt': date,
      'question': 'Q', 'isCorrect': correct,
    };
    await prefs.setString('quiz_results', jsonEncode([
      quizRecord('q2', '2026-01-03T00:00:00Z', true),
      quizRecord('q1', '2026-01-01T00:00:00Z', false),
    ]));
    await prefs.setString('quiz_retry_results', jsonEncode([
      retryRecord('r1', '2026-01-02T00:00:00Z', true),
    ]));
    expect(await status(), '해제');
    var stats = await StudyStorage.getSubjectWeakQuestionStats(
      semesterCode: '2026', subjectId: 'math');
    expect(stats['resolvedCount'], 1);
    expect(stats['resolutionRate'], 100.0);
    await prefs.setString('quiz_results', jsonEncode([
      quizRecord('q3', '2026-01-04T00:00:00Z', false),
      quizRecord('q2', '2026-01-03T00:00:00Z', true),
      quizRecord('q1', '2026-01-01T00:00:00Z', false),
    ]));
    expect(await status(), '취약');
    final item = (await StudyStorage.getQuestionAnalysis()).single;
    expect(item['consecutiveCorrect'], 0);
    stats = await StudyStorage.getSubjectWeakQuestionStats(
      semesterCode: '2026', subjectId: 'math');
    expect(stats['remainingWeakCount'], 1);
    expect(stats['resolutionRate'], 0.0);
  });

  test('오답 없는 정답은 취약에 등록하지 않고 이후 재풀이 오답은 초기화한다', () async {
    await quiz(correct: true);
    await quiz(correct: true);
    expect(await status(), '정상');
    expect((await StudyStorage.getSubjectWeakQuestionStats(
      semesterCode: '2026', subjectId: 'math'))['totalWeakCount'], 0);
    await retry(false);
    final item = (await StudyStorage.getQuestionAnalysis()).single;
    expect(item['consecutiveCorrect'], 0);
    expect(item['status'], '복습 필요');
  });

  test('누락·잘못된 날짜와 동일 시각을 결정적으로 처리하며 원본을 보존한다', () async {
    final prefs = await SharedPreferences.getInstance();
    final quizzes = [{
      'userId': 'alice', 'id': 'q', 'fileName': 'book.pdf',
      'semesterCode': '2026', 'subjectId': 'math', 'createdAt': 'invalid',
      'answers': [{'question': 'Q', 'type': 'multiple_choice', 'isCorrect': false}],
    }];
    final retries = [
      {'userId': 'alice', 'id': 'r1', 'fileName': 'book.pdf',
        'semesterCode': '2026', 'subjectId': 'math', 'question': 'Q',
        'isCorrect': true, 'createdAt': '2026-01-01T00:00:00Z'},
      {'userId': 'alice', 'id': 'r2', 'fileName': 'book.pdf',
        'semesterCode': '2026', 'subjectId': 'math', 'question': 'Q',
        'isCorrect': true, 'createdAt': '2026-01-01T00:00:00Z'},
    ];
    final rawQuizzes = jsonEncode(quizzes);
    final rawRetries = jsonEncode(retries);
    await prefs.setString('quiz_results', rawQuizzes);
    await prefs.setString('quiz_retry_results', rawRetries);
    expect(await status(), '해제');
    expect(prefs.getString('quiz_results'), rawQuizzes);
    expect(prefs.getString('quiz_retry_results'), rawRetries);
  });

  test('다른 계정과 소유자 없는 기존 기록 제외 및 원본 보존', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'quiz_results',
      jsonEncode([
        {
          'answers': [
            {'type': 'multiple_choice', 'isCorrect': true},
          ],
        },
      ]),
    );
    await quiz();
    StudyStorage.currentUserId = () => 'bob';
    expect((await StudyStorage.getMultipleChoiceStats())['hasData'], false);
    await quiz(correct: true);
    StudyStorage.currentUserId = () => 'alice';
    expect((await StudyStorage.getMultipleChoiceStats())['totalCount'], 1);
    expect((jsonDecode(prefs.getString('quiz_results')!) as List).length, 3);
    StudyStorage.currentUserId = () => null;
    expect(await StudyStorage.getQuestionAnalysis(), isEmpty);
  });

  testWidgets('기록이 없으면 분석 안내 화면 표시', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudyAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 분석할 객관식 학습 기록이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('분석 카드에 정답률과 해제 상태를 표시', (tester) async {
    await StudyStorage.saveQuizResult(
      fileName: '자료.pdf',
      subjectId: 'math',
      semesterCode: '2026',
      answers: [
        {
          'question': '화면 테스트 문제',
          'type': 'multiple_choice',
          'isCorrect': false,
        },
      ],
      correctCount: 0,
    );
    for (var i = 0; i < 2; i++) {
      await StudyStorage.saveRetryResult(
        question: '화면 테스트 문제',
        userAnswer: 'A',
        correctAnswer: 'A',
        isCorrect: true,
        fileName: '자료.pdf',
        subjectId: 'math',
        semesterCode: '2026',
      );
    }
    await tester.pumpWidget(const MaterialApp(home: StudyAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.text('66.7%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('학습 상태: 해제'), 300);
    expect(find.text('복습이 필요한 문제가 없습니다.'), findsOneWidget);
    expect(find.text('학습 상태: 해제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('손상된 기록은 오류 안내로 처리', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quiz_results', '{invalid');
    await tester.pumpWidget(const MaterialApp(home: StudyAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.text('학습 데이터를 불러오지 못했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
