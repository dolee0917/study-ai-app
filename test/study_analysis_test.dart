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
