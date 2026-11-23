import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  const questions = [
    {'type': 'multiple_choice', 'question': '문제', 'options': ['가', '나'],
      'answer': '가', 'explanation': '해설'},
  ];
  final normalizedQuestions = questions.map((q) => {...q, 'difficulty': 'unspecified'}).toList();

  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
