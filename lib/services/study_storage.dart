
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StudyStorage {
  static const String _storageKey = 'study_notes';

  // 저장된 학습 노트 목록 불러오기
  static Future<List<Map<String, dynamic>>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString(_storageKey);

    if (savedData == null) {
      return [];
    }

    final decoded = jsonDecode(savedData) as List<dynamic>;

    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // 새로운 학습 노트 저장하기
  static Future<void> saveNote({
    required String fileName,
    required String summaryText,
    required String originalText,
    List<dynamic> questions = const [],
    String? subjectId,
    String? semesterCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final notes = await loadNotes();

    final newNote = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'fileName': fileName,
      'summaryText': summaryText,
      'originalText': originalText,
      'questions': questions,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'createdAt': DateTime.now().toIso8601String(),
    };

    notes.insert(0, newNote);

    final success = await prefs.setString(
      _storageKey,
      jsonEncode(notes),
    );

    if (!success) {
      throw Exception('학습 노트를 저장하지 못했습니다.');
    }
  }

  // 복습문제 풀이 결과 저장
  static Future<void> saveQuizResult({
    required String fileName,
    required List<Map<String, dynamic>> answers,
    required int correctCount,
    String? subjectId,
    String? semesterCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 기존 복습 결과 불러오기
    final savedData = prefs.getString('quiz_results');

    List<dynamic> results = [];

    if (savedData != null) {
      results = jsonDecode(savedData) as List<dynamic>;
    }

    // 새로운 복습 결과
    final newResult = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'fileName': fileName,
      'answers': answers,
      'correctCount': correctCount,
      'totalQuestions': answers.length,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'createdAt': DateTime.now().toIso8601String(),
    };

    // 최신 결과가 맨 위에 표시되도록 저장
    results.insert(0, newResult);

    final success = await prefs.setString(
      'quiz_results',
      jsonEncode(results),
    );

    if (!success) {
      throw Exception('복습 결과를 저장하지 못했습니다.');
    }
  }

  // 저장된 복습 결과 목록 불러오기
  static Future<List<Map<String, dynamic>>> loadQuizResults() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('quiz_results');

    if (savedData == null) {
      return [];
    }

    final decoded = jsonDecode(savedData) as List<dynamic>;

    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // 오답 재풀이 결과 저장
  static Future<void> saveRetryResult({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    required bool isCorrect,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    const storageKey = 'quiz_retry_results';

    final savedData = prefs.getString(storageKey);

    final List<dynamic> results =
        savedData == null
            ? []
            : jsonDecode(savedData) as List<dynamic>;

    final newResult = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'question': question,
      'userAnswer': userAnswer,
      'correctAnswer': correctAnswer,
      'isCorrect': isCorrect,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'fileName': fileName,
      'createdAt': DateTime.now().toIso8601String(),
    };

    results.insert(0, newResult);

    final success = await prefs.setString(
      storageKey,
      jsonEncode(results),
    );

    if (!success) {
      throw Exception('재풀이 결과를 저장하지 못했습니다.');
    }
  }
  
  // 동일 문제의 연속 정답 횟수 계산
  static Future<int> getConsecutiveCorrectCount({
    required String question,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final savedData = prefs.getString('quiz_retry_results');

    if (savedData == null) {
      return 0;
    }

    final results = jsonDecode(savedData) as List<dynamic>;

    int consecutiveCorrect = 0;

    // 최신 재풀이 결과부터 확인
    for (final item in results) {
      final result = Map<String, dynamic>.from(item as Map);

      // 동일한 문제인지 확인
      if (result['question'] != question ||
          result['subjectId'] != subjectId ||
          result['semesterCode'] != semesterCode ||
          result['fileName'] != fileName) {
        continue;
      }

      if (result['isCorrect'] == true) {
        consecutiveCorrect++;
      } else {
        break;
      }
    }

    return consecutiveCorrect;
  }


}
