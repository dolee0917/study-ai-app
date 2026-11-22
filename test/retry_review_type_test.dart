import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_ai_app/services/study_storage.dart';

void main() {
  final originalUser = StudyStorage.currentUserId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StudyStorage.currentUserId = () => 'test-user';
  });
  tearDown(() => StudyStorage.currentUserId = originalUser);

  Future<void> save(bool correct, {String reviewType = 'wrong_answer_retry'}) =>
      StudyStorage.saveRetryResult(
        question: 'Q',
        userAnswer: correct ? 'A' : 'B',
        correctAnswer: 'A',
        isCorrect: correct,
        semesterCode: '2026-1',
        subjectId: 'math',
        fileName: 'book.pdf',
        reviewType: reviewType,
      );

  test('default review type and existing fields are saved', () async {
    await StudyStorage.saveRetryResult(
      question: 'Q', userAnswer: 'B', correctAnswer: 'A', isCorrect: false,
      semesterCode: '2026-1', subjectId: 'math', fileName: 'book.pdf',
    );
    final prefs = await SharedPreferences.getInstance();
    final records = jsonDecode(prefs.getString('quiz_retry_results')!) as List;
    expect(records.single, containsPair('reviewType', 'wrong_answer_retry'));
    expect(records.single, containsPair('question', 'Q'));
    expect(records.single, containsPair('userAnswer', 'B'));
    expect(records.single, containsPair('correctAnswer', 'A'));
    expect(records.single, containsPair('isCorrect', false));
    expect(records.single, containsPair('semesterCode', '2026-1'));
    expect(records.single, containsPair('subjectId', 'math'));
    expect(records.single, containsPair('fileName', 'book.pdf'));
    expect(records.single, containsPair('userId', 'test-user'));
    expect(records.single['id'], isNotEmpty);
    expect(DateTime.tryParse(records.single['createdAt']), isNotNull);
  });

  test('legacy records are interpreted without rewriting and reviews affect analysis', () async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = {
      'userId': 'test-user',
      'id': 'legacy',
      'question': 'Q',
      'userAnswer': 'B',
      'correctAnswer': 'A',
      'isCorrect': false,
      'semesterCode': '2026-1',
      'subjectId': 'math',
      'fileName': 'book.pdf',
      'createdAt': '2020-01-01T00:00:00.000',
      'extra': 'preserved',
    };
    final raw = jsonEncode([legacy]);
    await prefs.setString('quiz_retry_results', raw);

    var analysis = (await StudyStorage.getQuestionAnalysis()).single;
    expect(analysis['reviewType'], 'wrong_answer_retry');
    expect(analysis['wrongCount'], 1);
    expect(prefs.getString('quiz_retry_results'), raw);

    await save(false, reviewType: 'recommended_review');
    analysis = (await StudyStorage.getQuestionAnalysis()).single;
    expect(analysis['wrongCount'], 2);
    expect(analysis['status'], '취약');
    await save(true, reviewType: 'recommended_review');
    analysis = (await StudyStorage.getQuestionAnalysis()).single;
    expect(analysis['consecutiveCorrect'], 1);
    await save(true, reviewType: 'recommended_review');
    analysis = (await StudyStorage.getQuestionAnalysis()).single;
    expect(analysis['consecutiveCorrect'], 2);
    final weak = await StudyStorage.getWeakQuestionResolutionStats();
    expect(weak['resolvedCount'], 1);
    final stats = await StudyStorage.getMultipleChoiceStats();
    expect(stats['totalCount'], 4);
    expect(stats['correctCount'], 2);
    final records = jsonDecode(prefs.getString('quiz_retry_results')!) as List;
    expect(records.last, legacy);
    expect(records.first['reviewType'], 'recommended_review');
  });
}
