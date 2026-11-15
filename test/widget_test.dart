import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai_app/screens/quiz_screen.dart';

void main() {
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
}
