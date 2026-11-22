import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  Map<String, dynamic> question(String text, {bool legacy = false}) => {
    'type': 'multiple_choice', 'question': text, 'options': ['A', 'B'],
    if (legacy) 'correctAnswer': 'A' else 'answer': 'A', 'explanation': '설명',
  };
  Map<String, dynamic> note(String id, List<dynamic> questions,
      {String file = 'book.pdf', String semester = '2026-1', String subject = 'math'}) => {
    'id': id, 'fileName': file, 'semesterCode': semester,
    'subjectId': subject, 'questions': questions,
  };
  Future<void> seed(List<Map<String, dynamic>> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('study_notes', jsonEncode(notes));
  }
  Future<void> attempt(String text, bool correct, {String file = 'book.pdf'}) =>
      StudyStorage.saveQuizResult(fileName: file, semesterCode: '2026-1',
        subjectId: 'math', correctCount: correct ? 1 : 0,
        answers: [{'question': text, 'type': 'multiple_choice', 'isCorrect': correct}]);
  Future<void> retry(String text, bool correct) => StudyStorage.saveRetryResult(
    question: text, userAnswer: 'A', correctAnswer: 'A', isCorrect: correct,
    fileName: 'book.pdf', semesterCode: '2026-1', subjectId: 'math');
  Future<List<Map<String, dynamic>>> recommend({int limit = 20}) =>
      StudyStorage.getRecommendedReviewQuestions(
        semesterCode: '2026-1', subjectId: 'math', limit: limit);

  final originalUser = StudyStorage.currentUserId;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'test-user';
  });
  tearDown(() => StudyStorage.currentUserId = originalUser);

  test('미풀이, 미해소, 정답, 해제 순이며 푼 문제도 반복 추천한다', () async {
    await seed([note('one', [question('correct'), question('resolved'),
      question('weak'), question('unseen')])]);
    await attempt('correct', true);
    await attempt('weak', false);
    await attempt('resolved', false);
    await retry('resolved', true);
    await retry('resolved', true);
    await attempt('not-in-note', false);
    final result = await recommend();
    expect(result.map((q) => q['question']), ['unseen', 'weak', 'correct', 'resolved']);
    expect((await recommend(limit: 2)).map((q) => q['question']), ['unseen', 'weak']);
    expect(await recommend(limit: 0), isEmpty);
    expect(await recommend(limit: -1), isEmpty);
    expect(await recommend(), result);
  });

  test('학기와 과목을 구분하고 유효한 문제만 한 노트에서 중복 제거한다', () async {
    final source = question('valid');
    await seed([
      note('one', [source, source, question('legacy', legacy: true),
        {'type': 'short_answer', 'question': 'short', 'answer': 'A'},
        {'type': 'multiple_choice', 'question': 'bad', 'options': ['A'], 'answer': 'B'},
        {'type': 'multiple_choice', 'question': '', 'options': ['A'], 'answer': 'A'},
        {'type': 'multiple_choice', 'question': 'no options', 'answer': 'A'},
        {'type': 'multiple_choice', 'question': 'no answer', 'options': ['A']}]),
      note('other-subject', [question('science')], subject: 'science'),
      note('other-semester', [question('other')], semester: '2026-2'),
    ]);
    final result = await recommend();
    expect(result.map((q) => q['question']).toSet(), {'valid', 'legacy'});
    expect(result.length, 2);
    for (final q in result) {
      expect(q['correctAnswer'], 'A');
      expect(q['fileName'], 'book.pdf');
      expect(q['semesterCode'], '2026-1');
      expect(q['subjectId'], 'math');
      expect(q['explanation'], '설명');
    }
    final notes = await StudyStorage.loadNotes();
    expect((notes.first['questions'] as List).first, source);
  });

  test('서로 다른 노트의 동일 후보는 중복 제거하고 이력을 유지한다', () async {
    await seed([note('first', [question('same')]), note('second', [question('same')]),
      note('third', [question('single')], file: 'other.pdf')]);
    await attempt('same', false);
    await attempt('single', false, file: 'other.pdf');
    final result = await recommend();
    expect(result.map((q) => q['question']).toSet(), {'same', 'single'});
    expect(result.length, 2);
    expect(result.firstWhere((q) => q['question'] == 'same')['noteId'], 'first');
  });

  test('보기 순서나 정답, 파일이 다르면 후보를 유지하고 모호한 이력은 연결하지 않는다', () async {
    final differentOrder = {...question('same'), 'options': ['B', 'A']};
    final differentAnswer = {...question('same'), 'answer': 'B'};
    await seed([
      note('a', [question('same')]),
      note('b', [question('same')]),
      note('c', [differentOrder]),
      note('d', [differentAnswer]),
      note('e', [question('same')], file: 'other.pdf'),
      note('f', [question('different')]),
    ]);
    await attempt('same', false);
    final result = await recommend();
    expect(result.length, 5);
    expect(result.where((q) => q['question'] == 'same').length, 4);
    expect(result.where((q) => q['fileName'] == 'other.pdf').length, 1);
    expect(await StudyStorage.getQuestionLearningStatus(
      question: 'same', subjectId: 'math', semesterCode: '2026-1', fileName: 'book.pdf'),
      '판정 보류');
    expect((await StudyStorage.getSubjectWeakQuestionStats(
      semesterCode: '2026-1', subjectId: 'math'))['totalWeakCount'], 0);
  });

  test('동일 우선순위는 오답 횟수, 연속 정답 횟수와 식별 키 순으로 정렬한다', () async {
    await seed([note('one', [question('B'), question('A'), question('C'), question('D')])]);
    for (final text in ['A', 'B', 'C', 'D']) {
      await attempt(text, false);
      await attempt(text, false);
    }
    await attempt('D', false);
    await retry('C', true);
    expect((await recommend()).map((q) => q['question']), ['D', 'A', 'B', 'C']);
  });

  test('ID가 없는 이전 노트를 지원하며 저장된 문제가 없으면 빈 목록이다', () async {
    await attempt('record-only', false);
    expect(await recommend(), isEmpty);
    final legacy = note('ignored', [question('old')])..remove('id');
    await seed([legacy]);
    expect((await recommend()).single['question'], 'old');
  });
}
