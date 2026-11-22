import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyStorage {
  // 테스트에서 Firebase 초기화 없이 계정 격리를 검증하기 위한 조회 지점.
  static String? Function() currentUserId = () =>
      FirebaseAuth.instance.currentUser?.uid;

  static const String _storageKey = 'study_notes';
  static Future<void> _noteWrites = Future.value();

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
  static Future<String> saveNote({
    required String fileName,
    required String summaryText,
    required String originalText,
    List<dynamic> questions = const [],
    String? subjectId,
    String? semesterCode,
    String? noteId,
  }) async {
    final previous = _noteWrites;
    final completed = Completer<void>();
    _noteWrites = completed.future;
    await previous;
    try {
    final prefs = await SharedPreferences.getInstance();

    final notes = await loadNotes();

    final id = noteId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final index = notes.indexWhere((note) => note['id'] == id);
    if (index != -1 &&
        (notes[index]['fileName'] != fileName ||
            notes[index]['semesterCode'] != semesterCode ||
            notes[index]['subjectId'] != subjectId ||
            notes[index]['originalText'] != originalText ||
            notes[index]['summaryText'] != summaryText)) {
      throw StateError('학습 노트 식별 정보가 일치하지 않습니다.');
    }
    final newNote = {
      if (index != -1) ...notes[index],
      'id': id,
      'fileName': fileName,
      'summaryText': summaryText,
      'originalText': originalText,
      'questions': questions,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'createdAt': index == -1
          ? DateTime.now().toIso8601String()
          : notes[index]['createdAt'],
    };

    if (index == -1) {
      notes.insert(0, newNote);
    } else {
      notes[index] = newNote;
    }

    final success = await prefs.setString(_storageKey, jsonEncode(notes));

    if (!success) {
      throw Exception('학습 노트를 저장하지 못했습니다.');
    }
    return id;
    } finally {
      completed.complete();
    }
  }

  static Future<String> findExistingNoteId({
    required String fileName,
    required String summaryText,
    required String originalText,
    String? subjectId,
    String? semesterCode,
  }) async {
    final matches = (await loadNotes()).where((note) =>
        note['fileName'] == fileName && note['summaryText'] == summaryText &&
        note['originalText'] == originalText && note['subjectId'] == subjectId &&
        note['semesterCode'] == semesterCode).toList();
    if (matches.length != 1 || matches.single['id'] is! String ||
        (matches.single['id'] as String).isEmpty) {
      throw StateError('기존 학습 노트를 정확히 구분할 수 없습니다.');
    }
    return matches.single['id'] as String;
  }
  

  // 복습문제 풀이 결과 저장
  static Future<void> saveQuizResult({
    required String fileName,
    required List<Map<String, dynamic>> answers,
    required int correctCount,
    String? subjectId,
    String? semesterCode,
  }) async {
    final uid = currentUserId();
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final prefs = await SharedPreferences.getInstance();

    // 기존 복습 결과 불러오기
    final savedData = prefs.getString('quiz_results');

    List<dynamic> results = [];

    if (savedData != null) {
      results = jsonDecode(savedData) as List<dynamic>;
    }

    // 새로운 복습 결과
    final newResult = {
      'userId': uid,
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

    final success = await prefs.setString('quiz_results', jsonEncode(results));

    if (!success) {
      throw Exception('복습 결과를 저장하지 못했습니다.');
    }
  }

  // 저장된 복습 결과 목록 불러오기
  static Future<List<Map<String, dynamic>>> loadQuizResults() =>
      _owned('quiz_results');

  static Future<void> saveRetryResult({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    required bool isCorrect,
    String? subjectId,
    String? semesterCode,
    String? fileName,
    String reviewType = 'wrong_answer_retry',
  }) async {
    final uid = currentUserId();
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final prefs = await SharedPreferences.getInstance();

    const storageKey = 'quiz_retry_results';

    final savedData = prefs.getString(storageKey);

    final List<dynamic> results = savedData == null
        ? []
        : jsonDecode(savedData) as List<dynamic>;

    final newResult = {
      'userId': uid,
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'question': question,
      'userAnswer': userAnswer,
      'correctAnswer': correctAnswer,
      'isCorrect': isCorrect,
      'reviewType': reviewType,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'fileName': fileName,
      'createdAt': DateTime.now().toIso8601String(),
    };

    results.insert(0, newResult);

    final success = await prefs.setString(storageKey, jsonEncode(results));

    if (!success) {
      throw Exception('재풀이 결과를 저장하지 못했습니다.');
    }
  }

  // 동일 문제의 연속 정답 횟수 계산
  static Future<List<Map<String, dynamic>>> _owned(String key) async {
    final uid = currentUserId();
    if (uid == null) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw FormatException('$key: 목록 형식 오류');
    return decoded
        .map((a) => Map<String, dynamic>.from(a as Map))
        .where((a) => a['userId'] == uid)
        .toList();
  }

  // 오답 노트와 동일한 식별 기준. 구분자가 들어간 문자열도 안전하다.
  static String _key(Map<String, dynamic> a) => jsonEncode([
    a['semesterCode'],
    a['subjectId'],
    a['fileName'],
    a['question'],
  ]);

  static Future<List<Map<String, dynamic>>> _attempts() async {
    final quizzes = await loadQuizResults();
    final retries = await _owned('quiz_retry_results');
    return [
      for (final q in quizzes)
        for (final a in (q['answers'] as List<dynamic>? ?? []))
          {...q, ...Map<String, dynamic>.from(a as Map), 'isRetry': false},
      // 기존 재풀이는 객관식만 지원하며 type을 저장하지 않았다.
      for (final r in retries)
        {...r, 'reviewType': r['reviewType'] ?? 'wrong_answer_retry',
          'type': r['type'] ?? 'multiple_choice', 'isRetry': true},
        ].where((a) {
      final subjectId = a['subjectId']?.toString().trim();
      final semesterCode = a['semesterCode']?.toString().trim();

      return a['type'] == 'multiple_choice' &&
          subjectId != null &&
          subjectId.isNotEmpty &&
          semesterCode != null &&
          semesterCode.isNotEmpty;
    }).toList();
  }

  static Map<String, dynamic> _stats(List<Map<String, dynamic>> data) {
    final correct = data.where((a) => a['isCorrect'] == true).length;
    return {
      'totalCount': data.length,
      'correctCount': correct,
      'wrongCount': data.length - correct,
      'hasData': data.isNotEmpty,
      'accuracy': data.isEmpty ? 0.0 : correct / data.length * 100,
    };
  }

  static Future<Map<String, dynamic>> getMultipleChoiceStats({
    String? subjectId,
    String? semesterCode,
  }) async => _stats(
    (await _attempts())
        .where(
          (a) =>
              (subjectId == null || a['subjectId'] == subjectId) &&
              (semesterCode == null || a['semesterCode'] == semesterCode),
        )
        .toList(),
  );

  static Future<double> getMultipleChoiceAccuracy({
    String? subjectId,
    String? semesterCode,
  }) async =>
      (await getMultipleChoiceStats(
            subjectId: subjectId,
            semesterCode: semesterCode,
          ))['accuracy']
          as double;

  static Future<List<Map<String, dynamic>>> getSubjectAccuracyStats() async {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in await _attempts()) {
      groups
          .putIfAbsent(
            jsonEncode([a['semesterCode'], a['subjectId']]),
            () => [],
          )
          .add(a);
    }
    return [
      for (final g in groups.values)
        {
          'subjectId': g.first['subjectId'],
          'semesterCode': g.first['semesterCode'],
          ..._stats(g),
        },
    ];
  }

  static Future<List<Map<String, dynamic>>> getQuestionAnalysis() async {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in await _attempts()) {
      groups.putIfAbsent(_key(a), () => []).add(a);
    }
    return groups.values.map((g) {
      final wrong = g.where((a) => a['isCorrect'] == false).length;
      final retries = g.where((a) => a['isRetry'] == true).toList();
      final sorted = retries.asMap().entries.toList()
        ..sort((a, b) {
          final order =
              (DateTime.tryParse(b.value['createdAt']?.toString() ?? '') ??
                      DateTime(1970))
                  .compareTo(
                    DateTime.tryParse(a.value['createdAt']?.toString() ?? '') ??
                        DateTime(1970),
                  );
          return order != 0 ? order : a.key.compareTo(b.key);
        });
      var streak = 0;
      for (final a in sorted) {
        if (a.value['isCorrect'] != true) break;
        streak++;
      }
      final status = streak >= 2
          ? '해제'
          : wrong > 0 && streak == 1
          ? '개선 중'
          : wrong >= 2
          ? '취약'
          : wrong == 1
          ? '복습 필요'
          : '정상';
      return <String, dynamic>{
        ...g.first,
        'wrongCount': wrong,
        'consecutiveCorrect': streak,
        'status': status,
      };
    }).toList();
  }

    // 취약 문제 해소율 계산
  static Future<Map<String, dynamic>> getWeakQuestionResolutionStats() async {
    final questions = await getQuestionAnalysis();

    // 한 번이라도 오답이 발생한 고유 문제
    final weakQuestions = questions
        .where((q) => (q['wrongCount'] as int) > 0)
        .toList();

    // 현재 취약 상태가 해제된 문제
    final resolvedCount = weakQuestions
        .where((q) => q['status'] == '해제')
        .length;

    final totalWeakCount = weakQuestions.length;

    final resolutionRate = totalWeakCount == 0
        ? 0.0
        : resolvedCount / totalWeakCount * 100;

    return {
      'totalWeakCount': totalWeakCount,
      'resolvedCount': resolvedCount,
      'remainingWeakCount': totalWeakCount - resolvedCount,
      'resolutionRate': resolutionRate,
    };
  }

  static Future<Map<String, dynamic>> getSubjectWeakQuestionStats({
    required String semesterCode,
    required String subjectId,
  }) async {
    final questions = await getQuestionAnalysis();
    final weakQuestions = questions.where(
      (question) =>
          question['semesterCode'] == semesterCode &&
          question['subjectId'] == subjectId &&
          (question['wrongCount'] as int) > 0,
    );
    final totalWeakCount = weakQuestions.length;
    final resolvedCount =
        weakQuestions.where((question) => question['status'] == '해제').length;

    return {
      'totalWeakCount': totalWeakCount,
      'resolvedCount': resolvedCount,
      'remainingWeakCount': totalWeakCount - resolvedCount,
      'resolutionRate': totalWeakCount == 0
          ? 0.0
          : resolvedCount / totalWeakCount * 100,
    };
  }

  static Future<List<Map<String, dynamic>>> getRecommendedReviewQuestions({
    required String semesterCode,
    required String subjectId,
    required int limit,
  }) => _getRecommendedReviewQuestions(
    semesterCode: semesterCode, subjectId: subjectId, limit: limit,
  );

  static Future<int> getRecommendedReviewQuestionCount({
    required String semesterCode,
    required String subjectId,
  }) async => (await _getRecommendedReviewQuestions(
    semesterCode: semesterCode, subjectId: subjectId,
  )).length;

  static Future<List<Map<String, dynamic>>> _getRecommendedReviewQuestions({
    required String semesterCode,
    required String subjectId,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) return [];
    final notes = await loadNotes();
    final candidates = <String, Map<String, dynamic>>{};
    final historyOwners = <String, Set<int>>{};
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      final fileName = note['fileName'];
      final questions = note['questions'];
      if (note['semesterCode'] != semesterCode || note['subjectId'] != subjectId ||
          fileName is! String || fileName.trim().isEmpty || questions is! List) {
        continue;
      }
      for (final item in questions) {
        if (item is! Map || item['type'] != 'multiple_choice') continue;
        final question = item['question'];
        if (question is! String || question.trim().isEmpty) continue;
        final historyKey = _key({'semesterCode': semesterCode, 'subjectId': subjectId,
          'fileName': fileName, 'question': question});
        historyOwners.putIfAbsent(historyKey, () => <int>{}).add(index);
        final options = item['options'];
        final answer = item['answer'];
        final correct = answer is String && answer.trim().isNotEmpty
            ? answer
            : item['correctAnswer'];
        if (options is! List || options.isEmpty ||
            options.any((option) => option is! String || option.trim().isEmpty) ||
            correct is! String || correct.trim().isEmpty ||
            !options.any((option) => (option as String).trim() == correct.trim())) {
          continue;
        }
        final noteKey = jsonEncode([note['id'], index, historyKey]);
        candidates.putIfAbsent(noteKey, () => {
          'question': question,
          'options': List<dynamic>.from(options),
          'correctAnswer': correct,
          'explanation': item['explanation'] is String ? item['explanation'] : '',
          'fileName': fileName,
          'semesterCode': semesterCode,
          'subjectId': subjectId,
          if (note['id'] is String) 'noteId': note['id'],
        });
      }
    }

    final histories = <String, Map<String, dynamic>>{
      for (final item in await getQuestionAnalysis()) _key(item): item,
    };
    final ranked = candidates.entries.toList();
    Map<String, dynamic>? history(Map<String, dynamic> candidate) {
      final key = _key(candidate);
      // 기존 풀이 기록에는 노트 ID가 없으므로 하나의 노트에만 연결될 때 사용한다.
      return historyOwners[key]?.length == 1 ? histories[key] : null;
    }
    int priority(Map<String, dynamic>? item) {
      if (item == null) return 0;
      if (item['status'] == '해제') return 3;
      if ((item['wrongCount'] as int) > 0) return 1;
      return 2;
    }
    ranked.sort((a, b) {
      final ah = history(a.value);
      final bh = history(b.value);
      final order = priority(ah).compareTo(priority(bh));
      if (order != 0) return order;
      final wrong = ((bh?['wrongCount'] as int?) ?? 0)
          .compareTo((ah?['wrongCount'] as int?) ?? 0);
      if (wrong != 0) return wrong;
      final streak = ((ah?['consecutiveCorrect'] as int?) ?? 0)
          .compareTo((bh?['consecutiveCorrect'] as int?) ?? 0);
      return streak != 0 ? streak : a.key.compareTo(b.key);
    });
    final selected = limit == null ? ranked : ranked.take(limit);
    return selected.map((entry) => entry.value).toList();
  }

  static int calculateTodayReviewCount({
    required int remainingWeakCount,
    required int daysUntilExam,
  }) {
    if (remainingWeakCount <= 0 || daysUntilExam < 0) return 0;

    final count = daysUntilExam <= 1
        ? remainingWeakCount
        : remainingWeakCount ~/ daysUntilExam +
            (remainingWeakCount % daysUntilExam == 0 ? 0 : 1);
    return count > 10 ? 10 : count;
  }

  static int calculateTodayRecommendedCount({
    required int availableQuestionCount,
    required int daysUntilExam,
  }) => calculateTodayReviewCount(
    remainingWeakCount: availableQuestionCount,
    daysUntilExam: daysUntilExam,
  );

  static Future<Map<String, dynamic>> _find({
    required String question,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async {
    final key = _key({
      'question': question,
      'subjectId': subjectId,
      'semesterCode': semesterCode,
      'fileName': fileName,
    });
    return (await getQuestionAnalysis()).firstWhere(
      (a) => _key(a) == key,
      orElse: () => {'wrongCount': 0, 'consecutiveCorrect': 0, 'status': '정상'},
    );
  }

  static Future<int> getQuestionWrongCount({
    required String question,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async =>
      (await _find(
            question: question,
            subjectId: subjectId,
            semesterCode: semesterCode,
            fileName: fileName,
          ))['wrongCount']
          as int;

  static Future<int> getConsecutiveCorrectCount({
    required String question,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async =>
      (await _find(
            question: question,
            subjectId: subjectId,
            semesterCode: semesterCode,
            fileName: fileName,
          ))['consecutiveCorrect']
          as int;

  static Future<String> getQuestionLearningStatus({
    required String question,
    String? subjectId,
    String? semesterCode,
    String? fileName,
  }) async =>
      (await _find(
            question: question,
            subjectId: subjectId,
            semesterCode: semesterCode,
            fileName: fileName,
          ))['status']
          as String;
}
