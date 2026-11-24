import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai_app/screens/quiz_history_detail_screen.dart';

void main() {
  test('저장된 객관식과 주관식을 원본 노트 없이 식별자와 개념까지 복원한다', () {
    final restored = restoreQuizQuestions([
      {'type': 'multiple_choice', 'question': 'Q', 'options': ['A', 'B'],
        'correctAnswer': 'A', 'explanation': '해설', 'questionId': 'q1',
        'noteId': 'n1', 'concept': '핵심', 'subConcept': '세부', 'difficulty': 'easy'},
      {'type': 'short_answer', 'question': 'S', 'options': [],
        'correctAnswer': '정답', 'questionId': 'q2', 'noteId': 'n1',
        'concept': null, 'subConcept': '세부2', 'difficulty': 'hard'},
    ]);
    expect(restored[0]['questionId'], 'q1');
    expect(restored[0]['noteId'], 'n1');
    expect(restored[0]['concept'], '핵심');
    expect(restored[0]['subConcept'], '세부');
    expect(restored[0]['difficulty'], 'easy');
    expect(restored[0]['options'], ['A', 'B']);
    expect(restored[0]['answer'], 'A');
    expect(restored[1]['type'], 'short_answer');
    expect(restored[1]['questionId'], 'q2');
    expect(restored[1]['noteId'], 'n1');
    expect(restored[1].containsKey('concept'), isTrue);
    expect(restored[1]['concept'], isNull);
    expect(restored[1]['subConcept'], '세부2');
    expect(restored[1]['difficulty'], 'hard');
  });

  test('신규 필드 없는 기존 문제는 식별자나 개념을 생성하지 않는다', () {
    final restored = restoreQuizQuestions([
      {'question': 'Q', 'options': ['A'], 'correctAnswer': 'A'},
      {'question': 'S', 'correctAnswer': '정답'},
    ]);
    expect(restored[0]['type'], 'multiple_choice');
    expect(restored[1]['type'], 'short_answer');
    for (final question in restored) {
      for (final key in ['questionId', 'noteId', 'concept', 'subConcept', 'difficulty']) {
        expect(question.containsKey(key), isFalse);
      }
    }
  });
}
