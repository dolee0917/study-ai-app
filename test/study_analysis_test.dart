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

  testWidgets('정답률을 표시하고 문제 목록과 해소율을 표시하지 않는다', (tester) async {
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
    final overallChart = find.byKey(const ValueKey('overall_accuracy_chart'));
    final overallArea = find.ancestor(
      of: overallChart,
      matching: find.byWidgetPredicate((widget) =>
          widget is SizedBox && widget.width == 118 && widget.height == 118),
    );
    expect(find.descendant(of: overallArea, matching: find.text('66.7%')), findsOneWidget);
    final chart = tester.widget<CircularProgressIndicator>(
      overallChart,
    );
    expect(chart.value, closeTo(2 / 3, .0001));
    expect(find.text('3회'), findsOneWidget);
    expect(find.text('2회'), findsOneWidget);
    expect(find.text('1회'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('과목별 성취도'), 200);
    final subjectCard = find.ancestor(
      of: find.text('정답 2회 · 오답 1회 · 전체 3회'),
      matching: find.byType(Container),
    ).first;
    expect(find.descendant(of: subjectCard, matching: find.text('66.7%')), findsOneWidget);
    expect(find.text('정답 2회 · 오답 1회 · 전체 3회'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('남은 복습 대상: 0문제'), 200);
    expect(find.byKey(const ValueKey('status_해제')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('status_해제'))).data, '1문제');
    for (final status in ['복습 필요', '취약', '개선 중']) {
      expect(tester.widget<Text>(find.byKey(ValueKey('status_$status'))).data, '0문제');
    }
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '취약 문제 복습하기 (준비 중)')).onPressed, isNull);
    expect(find.text('취약 문제 목록'), findsNothing);
    expect(find.text('문제별 학습 상태'), findsNothing);
    expect(find.text('학습 상태: 해제'), findsNothing);
    expect(find.text('복습이 필요한 문제가 없습니다.'), findsNothing);
    expect(find.text('취약 문제 해소율'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('상태별 고유 문제와 남은 복습 대상을 집계한다', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final records = <Map<String, dynamic>>[];
    void add(String question, int day, bool correct) {
      records.add({
        'id': '$question-$day', 'userId': 'alice', 'fileName': '자료.pdf',
        'semesterCode': '2026-1', 'subjectId': 'math',
        'createdAt': '2026-01-0${day}T00:00:00Z',
        'answers': [{'question': question, 'type': 'multiple_choice', 'isCorrect': correct}],
      });
    }
    add('review', 1, false);
    add('weak', 1, false); add('weak', 2, false);
    add('improving', 1, false); add('improving', 2, true);
    add('resolved', 1, false); add('resolved', 2, true); add('resolved', 3, true);
    add('normal', 1, true);
    await prefs.setString('quiz_results', jsonEncode(records));
    await tester.pumpWidget(const MaterialApp(home: StudyAnalysisScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('남은 복습 대상: 3문제'), 200);
    for (final status in ['복습 필요', '취약', '개선 중', '해제']) {
      expect(tester.widget<Text>(find.byKey(ValueKey('status_$status'))).data, '1문제');
    }
    expect(find.text('남은 복습 대상: 3문제'), findsOneWidget);
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

  testWidgets('학기와 과목 조합에 따라 통계와 문제 상태를 필터링한다', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quiz_results', jsonEncode([
      {'userId': 'alice', 'id': 'a', 'fileName': 'a.pdf',
        'semesterCode': '2025-1', 'subjectId': 'math', 'createdAt': '2025-01-01',
        'answers': [{'question': 'A', 'type': 'multiple_choice', 'isCorrect': false}]},
      {'userId': 'alice', 'id': 'b', 'fileName': 'b.pdf',
        'semesterCode': '2026-2', 'subjectId': 'math', 'createdAt': '2026-01-01',
        'answers': [{'question': 'B', 'type': 'multiple_choice', 'isCorrect': true}]},
      {'userId': 'bob', 'id': 'c', 'fileName': 'c.pdf',
        'semesterCode': '2024-1', 'subjectId': 'other', 'createdAt': '2024-01-01',
        'answers': [{'question': 'C', 'type': 'multiple_choice', 'isCorrect': false}]},
    ]));
    await tester.pumpWidget(MaterialApp(home: StudyAnalysisScreen(
      registeredSubjectsLoader: (_) async => [
        {'semesterCode': '2025-1', 'subjectId': 'math', 'name': '수학'},
        {'semesterCode': '2026-2', 'subjectId': 'math', 'name': '수학'},
        {'semesterCode': '2026-2', 'subjectId': 'empty', 'name': '물리'},
      ],
    )));
    await tester.pumpAndSettle();
    DropdownButton<String> semester() => tester.widget(find.byKey(const ValueKey('semester_filter')));
    DropdownButton<String> subject() => tester.widget(find.byKey(const ValueKey('subject_filter')));
    expect(semester().value, '');
    expect(subject().value, '');
    expect(tester.widget<CircularProgressIndicator>(find.byKey(const ValueKey('overall_accuracy_chart'))).value, .5);
    await tester.tap(find.byKey(const ValueKey('subject_filter')));
    await tester.pumpAndSettle();
    expect(find.text('수학 (2025학년도 1학기)'), findsWidgets);
    expect(find.text('수학 (2026학년도 2학기)'), findsWidgets);
    await tester.tap(find.text('수학 (2025학년도 1학기)').last);
    await tester.pumpAndSettle();
    expect(tester.widget<CircularProgressIndicator>(find.byKey(const ValueKey('overall_accuracy_chart'))).value, 0);
    await tester.scrollUntilVisible(find.text('남은 복습 대상: 1문제'), 200);
    expect(tester.widget<Text>(find.byKey(const ValueKey('status_복습 필요'))).data, '1문제');
    semester().onChanged!('2026-2');
    await tester.pumpAndSettle();
    expect(subject().value, '');
    expect(tester.widget<CircularProgressIndicator>(find.byKey(const ValueKey('overall_accuracy_chart'))).value, 1);
    subject().onChanged!(jsonEncode(['2026-2', 'empty']));
    await tester.pumpAndSettle();
    expect(find.text('선택한 범위에 학습 기록이 없습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('semester_filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('subject_filter')), findsOneWidget);
    subject().onChanged!('');
    await tester.pumpAndSettle();
    semester().onChanged!('');
    await tester.pumpAndSettle();
    expect(tester.widget<CircularProgressIndicator>(find.byKey(const ValueKey('overall_accuracy_chart'))).value, .5);
    expect(tester.takeException(), isNull);
  });
}
