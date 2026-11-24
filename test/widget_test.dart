import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai_app/screens/quiz_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';
import 'package:study_ai_app/screens/quiz_history_detail_screen.dart';
import 'package:study_ai_app/screens/wrong_answer_screen.dart';
import 'package:study_ai_app/screens/wrong_answer_retry_screen.dart';

void main() {
  final originalUser = StudyStorage.currentUserId;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'alice';
  });
  tearDown(() => StudyStorage.currentUserId = originalUser);
  // 화면을 직접 실행해 Firebase와 외부 API 호출을 피합니다.
  // 완료 버튼을 누르지 않아 실제 로컬 저장소도 사용하지 않습니다.
  const multipleChoice = {
    'type': 'multiple_choice',
    'question': '대한민국의 수도는?',
    'options': ['서울', '부산'],
    'answer': '서울',
    'explanation': '대한민국의 수도는 서울입니다.',
  };

  Future<void> openQuiz(
    WidgetTester tester,
    List<Map<String, dynamic>> questions,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(questions: questions, fileName: '테스트 자료.pdf'),
      ),
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('문제가 없으면 안내를 표시하고 풀이 버튼을 숨긴다', (tester) async {
    await openQuiz(tester, []);
    expect(find.text('생성된 문제가 없습니다.'), findsOneWidget);
    expect(find.text('정답 확인'), findsNothing);
  });

  for (final choice in ['서울', '부산']) {
    testWidgets('객관식 $choice 선택을 채점하고 정답과 해설을 표시한다', (tester) async {
      await openQuiz(tester, [multipleChoice]);
      await tapText(tester, '정답 확인');
      expect(find.text('정답: 서울'), findsNothing);
      expect(find.text('학습 결과 확인'), findsNothing);

      await tapText(tester, choice);
      await tapText(tester, '정답 확인');
      expect(
        find.text(choice == '서울' ? '정답입니다!' : '오답입니다.'),
        findsOneWidget,
      );
      expect(
        find.text(choice == '서울' ? '오답입니다.' : '정답입니다!'),
        findsNothing,
      );
      expect(find.text('정답: 서울'), findsOneWidget);
      expect(find.text('해설: 대한민국의 수도는 서울입니다.'), findsOneWidget);
      expect(find.text('학습 결과 확인'), findsOneWidget);
    });
  }

  testWidgets('다음 문제에서 답안을 초기화하고 주관식은 모범답안으로 확인한다', (tester) async {
    await openQuiz(tester, [
      multipleChoice,
      {
        'type': 'short_answer',
        'question': '광합성을 설명하세요.',
        'options': <String>[],
        'answer': '빛 에너지를 화학 에너지로 전환하는 과정',
        'explanation': '식물은 빛을 이용해 유기물을 합성합니다.',
      },
    ]);
    await tapText(tester, '서울');
    await tapText(tester, '정답 확인');
    await tapText(tester, '다음 문제');

    expect(find.text('2 / 2 문제'), findsOneWidget);
    expect(find.text('정답입니다!'), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tapText(tester, '정답 확인');
    expect(find.text('모범답안 확인'), findsNothing);

    await tester.enterText(find.byType(TextField), '식물이 빛으로 양분을 만드는 과정');
    await tapText(tester, '정답 확인');
    expect(find.text('모범답안 확인'), findsOneWidget);
    expect(find.text('정답: 빛 에너지를 화학 에너지로 전환하는 과정'), findsOneWidget);
    expect(find.text('해설: 식물은 빛을 이용해 유기물을 합성합니다.'), findsOneWidget);
    expect(find.text('정답입니다!'), findsNothing);
    expect(find.text('오답입니다.'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('객관식과 주관식 결과에 식별자, 개념, 난이도를 저장한다', (tester) async {
    await openQuiz(tester, [
      {...multipleChoice, 'questionId': 'mc-id', 'noteId': 'note',
        'concept': '핵심', 'subConcept': '세부', 'difficulty': 'easy'},
      {'type': 'short_answer', 'question': '서술', 'answer': '모범답안',
        'questionId': 'short-id', 'noteId': 'note', 'concept': null,
        'subConcept': '세부2', 'difficulty': 'hard'},
    ]);
    await tapText(tester, '부산');
    await tapText(tester, '정답 확인');
    await tapText(tester, '다음 문제');
    await tester.enterText(find.byType(TextField), '내 답안');
    await tapText(tester, '정답 확인');
    await tapText(tester, '학습 결과 확인');
    final answers = (await StudyStorage.loadQuizResults()).single['answers'] as List;
    expect(answers[0]['questionId'], 'mc-id');
    expect(answers[0]['noteId'], 'note');
    expect(answers[0]['concept'], '핵심');
    expect(answers[0]['subConcept'], '세부');
    expect(answers[0]['difficulty'], 'easy');
    expect(answers[0]['isCorrect'], isFalse);
    expect(answers[1]['questionId'], 'short-id');
    expect(answers[1]['noteId'], 'note');
    expect(answers[1]['concept'], isNull);
    expect(answers[1]['subConcept'], '세부2');
    expect(answers[1]['difficulty'], 'hard');
    expect(answers[1]['isCorrect'], isNull);
  });

  testWidgets('일반 풀이 도중 계정이 바뀌면 결과를 저장하지 않는다', (tester) async {
    await openQuiz(tester, [multipleChoice]);
    await tapText(tester, '서울');
    await tapText(tester, '정답 확인');
    StudyStorage.currentUserId = () => 'bob';
    await tapText(tester, '학습 결과 확인');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quiz_results'), isNull);
    expect(find.textContaining('복습 결과 저장에 실패했습니다'), findsOneWidget);
  });

  testWidgets('기존 문제에 없는 식별자와 개념을 생성하지 않는다', (tester) async {
    await openQuiz(tester, [multipleChoice]);
    await tapText(tester, '서울');
    await tapText(tester, '정답 확인');
    await tapText(tester, '학습 결과 확인');
    final prefs = await SharedPreferences.getInstance();
    final records = jsonDecode(prefs.getString('quiz_results')!) as List;
    final answer = records.single['answers'][0] as Map;
    for (final key in ['questionId', 'noteId', 'concept', 'subConcept', 'difficulty']) {
      expect(answer.containsKey(key), isFalse);
    }
    expect(answer['isCorrect'], isTrue);
  });

  testWidgets('노트 없이 저장된 문제를 복원해 다시 풀어도 동일 ID와 개념을 저장한다', (tester) async {
    final restored = restoreQuizQuestions([{
      'question': 'Q', 'type': 'multiple_choice', 'options': ['A', 'B'],
      'correctAnswer': 'A', 'questionId': 'q1', 'noteId': 'n1',
      'concept': '핵심', 'subConcept': '세부', 'difficulty': 'easy',
    }]);
    await openQuiz(tester, restored);
    await tapText(tester, 'A');
    await tapText(tester, '정답 확인');
    await tapText(tester, '학습 결과 확인');
    final saved = ((await StudyStorage.loadQuizResults()).single['answers'] as List).single;
    expect(saved['questionId'], 'q1');
    expect(saved['noteId'], 'n1');
    expect(saved['concept'], '핵심');
    expect(saved['subConcept'], '세부');
    expect(saved['difficulty'], 'easy');
  });

  testWidgets('오답 목록은 이력에서 재풀이 화면으로 메타데이터를 전달한다', (tester) async {
    await StudyStorage.saveQuizResult(fileName: 'book.pdf', semesterCode: '2026-1',
      subjectId: 'math', correctCount: 0, answers: [{
        'question': '오답 문제', 'type': 'multiple_choice', 'isCorrect': false,
        'userAnswer': 'B', 'correctAnswer': 'A', 'options': ['A', 'B'],
        'questionId': 'q1', 'noteId': 'n1', 'concept': '핵심',
        'subConcept': '세부', 'difficulty': 'easy',
      }]);
    await tester.pumpWidget(const MaterialApp(home: WrongAnswerScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다시 풀기'));
    await tester.tap(find.text('다시 풀기'));
    await tester.pumpAndSettle();
    final question = tester.widget<WrongAnswerRetryScreen>(find.byType(WrongAnswerRetryScreen)).question;
    expect(question['questionId'], 'q1');
    expect(question['noteId'], 'n1');
    expect(question['concept'], '핵심');
    expect(question['subConcept'], '세부');
    expect(question['difficulty'], 'easy');
  });
}
