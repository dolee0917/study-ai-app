import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  final originalUser = StudyStorage.currentUserId;
  const questions = [
    {'type': 'multiple_choice', 'question': '문제', 'options': ['가', '나'],
      'answer': '가', 'explanation': '해설'},
  ];
  final normalizedQuestions = questions.map((q) => {...q, 'difficulty': 'unspecified'}).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'alice';
  });
  tearDown(() => StudyStorage.currentUserId = originalUser);

  Future<String> save(String id, {String subject = 'math',
      String semester = '2026-1', String original = '본문',
      List<dynamic> items = const []}) => StudyStorage.saveNote(
    noteId: id, fileName: 'same.pdf', summaryText: '요약',
    originalText: original, semesterCode: semester, subjectId: subject,
    questions: items,
  );

  test('노트 저장 후 생성 문제 갱신과 생성 먼저 저장 모두 한 노트를 유지한다', () async {
    await save('first');
    await save('first', items: questions);
    await save('second', items: questions);
    var notes = await StudyStorage.loadNotes();
    expect(notes.length, 2);
    expect(notes.firstWhere((n) => n['id'] == 'first')['questions'], normalizedQuestions);
    expect(notes.firstWhere((n) => n['id'] == 'second')['questions'], normalizedQuestions);
    await save('second', items: questions);
    notes = await StudyStorage.loadNotes();
    expect(notes.length, 2);
  });

  test('같은 파일명의 다른 학기, 과목과 재업로드를 ID로 구분한다', () async {
    await save('a', items: questions);
    await save('b', subject: 'science');
    await save('c', semester: '2026-2');
    await save('d', original: '다른 본문');
    await save('e');
    final notes = await StudyStorage.loadNotes();
    expect(notes.length, 5);
    expect(notes.firstWhere((n) => n['id'] == 'a')['questions'], normalizedQuestions);
    expect(notes.where((n) => n['id'] != 'a').every((n) => (n['questions'] as List).isEmpty), isTrue);
    await expectLater(save('a', original: '다른 본문'), throwsStateError);
  });

  test('기존 노트는 정확히 하나만 일치할 때 갱신하고 중복은 거부한다', () async {
    final id = await StudyStorage.saveNote(fileName: 'same.pdf', summaryText: '요약',
      originalText: '본문', semesterCode: '2026-1', subjectId: 'math');
    Future<String> find() => StudyStorage.findExistingNoteId(fileName: 'same.pdf',
      summaryText: '요약', originalText: '본문', semesterCode: '2026-1', subjectId: 'math');
    expect(await find(), id);
    await save(id, items: questions);
    expect((await StudyStorage.loadNotes()).single['questions'], normalizedQuestions);
    await save('duplicate');
    await expectLater(find(), throwsStateError);
  });

  test('직렬화 실패 또는 손상된 저장 데이터에서 기존 데이터를 변경하지 않는다', () async {
    await save('a', items: questions);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('study_notes');
    await expectLater(save('a', items: [Object()]), throwsA(isA<JsonUnsupportedObjectError>()));
    expect(prefs.getString('study_notes'), before);
    await prefs.setString('study_notes', '{invalid');
    await expectLater(save('b'), throwsFormatException);
    expect(prefs.getString('study_notes'), '{invalid');
  });

  test('여러 노트를 동시에 저장해도 각각 보존한다', () async {
    await Future.wait([save('one'), save('two'), save('three')]);
    expect((await StudyStorage.loadNotes()).map((note) => note['id']).toSet(),
      {'one', 'two', 'three'});
  });

  test('난이도를 정규화해 읽고 다른 필드와 기존 저장 원본을 보존한다', () async {
    final items = [
      for (final difficulty in ['easy', 'medium', 'hard', 'invalid'])
        {...questions.single, 'difficulty': difficulty},
      questions.single,
    ];
    await save('a', items: items);
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('study_notes');
    final loaded = (await StudyStorage.loadNotes()).single['questions'] as List;
    expect(loaded.map((q) => q['difficulty']),
        ['easy', 'medium', 'hard', 'unspecified', 'unspecified']);
    for (final question in loaded) {
      final otherFields = Map<String, dynamic>.from(question)..remove('difficulty');
      expect(otherFields, questions.single);
    }
    expect(prefs.getString('study_notes'), before);
    await save('b');
    final raw = jsonDecode(prefs.getString('study_notes')!) as List;
    expect(raw.firstWhere((n) => n['id'] == 'a')['questions'], items);
  });

  test('신규 문제 ID와 개념을 정규화하고 실제 노트 ID와 함께 보존한다', () async {
    final source = [
      {'type': 'multiple_choice', 'question': 'Q', 'answer': 'A', 'options': ['A'],
        'concept': ' 핵심  개념 ', 'subConcept': ' 세부\t개념 '},
      {'type': 'short_answer', 'question': 'Q', 'answer': 'A',
        'concept': 12, 'subConcept': ' 유효 '},
      {'type': 'short_answer', 'question': 'R', 'answer': 'B', 'subConcept': []},
    ];
    final generated = StudyStorage.prepareGeneratedQuestions(source);
    final regenerated = StudyStorage.prepareGeneratedQuestions(source);
    final ids = generated.map((q) => q['questionId'] as String).toSet();
    expect(ids.length, 3);
    expect(ids.every((id) => id.isNotEmpty), isTrue);
    expect(ids.intersection(regenerated.map((q) => q['questionId'] as String).toSet()), isEmpty);
    expect(generated[0]['concept'], '핵심 개념');
    expect(generated[0]['subConcept'], '세부 개념');
    expect(generated[1]['concept'], isNull);
    expect(generated[1]['subConcept'], '유효');
    expect(generated[2]['concept'], isNull);
    expect(generated[2]['subConcept'], isNull);
    final id = await StudyStorage.saveNote(fileName: 'same.pdf', summaryText: '요약',
      originalText: '본문', semesterCode: '2026-1', subjectId: 'math', questions: generated);
    final note = (await StudyStorage.loadOwnedNotes()).single;
    expect(note['id'], id);
    expect(note['userId'], 'alice');
    expect(note['semesterCode'], '2026-1');
    expect(note['subjectId'], 'math');
    final stored = note['questions'] as List;
    expect(stored.map((q) => q['questionId']).toSet(), ids);
    expect(stored.every((q) => q['noteId'] == id), isTrue);
    expect((await StudyStorage.loadNotes()).single['questions'], stored);
    await save(id, items: generated);
    expect((await StudyStorage.loadOwnedNotes()).length, 1);
  });

  test('소유자 없는 노트와 다른 사용자 노트를 보존하고 본인 노트만 갱신한다', () async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = {'id': 'legacy', 'fileName': 'same.pdf', 'summaryText': '요약',
      'originalText': '본문', 'semesterCode': '2026-1', 'subjectId': 'math',
      'questions': questions};
    await prefs.setString('study_notes', jsonEncode([legacy]));
    await expectLater(save('legacy', items: questions), throwsStateError);
    await save('alice-note', items: questions);
    expect((await StudyStorage.loadOwnedNotes()).single['id'], 'alice-note');
    StudyStorage.currentUserId = () => 'bob';
    await expectLater(save('alice-note'), throwsStateError);
    expect(await StudyStorage.loadOwnedNotes(), isEmpty);
    await save('bob-note');
    StudyStorage.currentUserId = () => 'alice';
    await save('alice-note', items: questions);
    final raw = jsonDecode(prefs.getString('study_notes')!) as List;
    expect(raw.firstWhere((n) => n['id'] == 'legacy'), legacy);
    expect(raw.firstWhere((n) => n['id'] == 'bob-note')['userId'], 'bob');
    expect(raw.where((n) => n['id'] == 'alice-note').length, 1);
  });

  test('예상 사용자와 로그인 사용자가 다르면 노트와 풀이 이력을 변경하지 않는다', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quiz_results', '[]');
    await expectLater(StudyStorage.saveNote(noteId: 'n', fileName: 'same.pdf',
      summaryText: '요약', originalText: '본문', expectedUserId: 'bob'), throwsStateError);
    expect(prefs.getString('study_notes'), isNull);
    expect(prefs.getString('quiz_results'), '[]');
  });

  test('추천 후보에서 다른 사용자의 노트를 제외하고 무소유 노트는 유지한다', () async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> note(String id, String text, [String? uid]) => {
      'id': id, 'userId': ?uid, 'fileName': '$id.pdf',
      'semesterCode': '2026-1', 'subjectId': 'math',
      'questions': [{'type': 'multiple_choice', 'question': text,
        'options': ['A', 'B'], 'answer': 'A'}],
    };
    await prefs.setString('study_notes', jsonEncode([
      note('own', '내 문제', 'alice'), note('other', '다른 문제', 'bob'),
      note('legacy', '이전 문제'),
    ]));
    final candidates = await StudyStorage.getRecommendedReviewQuestions(
      semesterCode: '2026-1', subjectId: 'math', limit: 10);
    expect(candidates.map((q) => q['question']).toSet(), {'내 문제', '이전 문제'});
    expect((await StudyStorage.loadOwnedNotes()).single['id'], 'own');
  });
}
