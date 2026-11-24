
import 'package:flutter/material.dart';
import '../services/study_storage.dart';

class QuizScreen extends StatefulWidget {
  final List<dynamic> questions;
  final String fileName;
  // 과목 및 학기 정보
  final String? subjectId;
  final String? semesterCode;

  const QuizScreen({
    super.key,
    required this.questions,
    required this.fileName,
    this.subjectId,
    this.semesterCode,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final String? _sessionUserId;
  int currentIndex = 0;
  int correctCount = 0;

  String? selectedAnswer;
  final TextEditingController answerController =
      TextEditingController();
  final List<Map<String, dynamic>> answerHistory = [];

  bool isAnswered = false;
  bool isCorrect = false;

  @override
  void initState() {
    super.initState();
    _sessionUserId = StudyStorage.currentUserId();
  }

  @override
  void dispose() {
    answerController.dispose();
    super.dispose();
  }

  void recordAnswer({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    required bool? isCorrect,
    required String explanation,
    required dynamic options,
    required String type,
    required Map<String, dynamic> source,
  }) {
    answerHistory.add({
      'question': question,
      'userAnswer': userAnswer,
      'correctAnswer': correctAnswer,
      'isCorrect': isCorrect,
      'explanation': explanation,
      'options': options,
      'type': type,
      for (final key in ['questionId', 'noteId', 'concept', 'subConcept', 'difficulty'])
        if (source.containsKey(key)) key: source[key],
    });
  }
  
  void checkAnswer() {
    // 이미 정답을 확인한 문제는 중복 기록하지 않음
    if (isAnswered) return;

    final question = widget.questions[currentIndex]
        as Map<String, dynamic>;

    final correctAnswer =
        question['answer'].toString().trim();

    final userAnswer =
        question['type'] == 'multiple_choice'
            ? (selectedAnswer ?? '')
            : answerController.text.trim();

    if (userAnswer.isEmpty) return;

    // 객관식만 자동 채점
    final bool? answerIsCorrect =
        question['type'] == 'multiple_choice'
            ? userAnswer == correctAnswer
            : null;

    setState(() {
      isAnswered = true;

      if (answerIsCorrect != null) {
        isCorrect = answerIsCorrect;

        if (answerIsCorrect) {
          correctCount++;
        }
      }
    });

    // 사용자 답안 및 정답 여부 기록
    recordAnswer(
      question: question['question'].toString(),
      userAnswer: userAnswer,
      correctAnswer: correctAnswer,
      isCorrect: answerIsCorrect,
      explanation: question['explanation']?.toString() ?? '',
      options: question['options'],
      type: question['type']?.toString() ?? 'short_answer',
      source: question,
    );
  }


  void nextQuestion() {
    if (currentIndex < widget.questions.length - 1) {
      setState(() {
        currentIndex++;
        selectedAnswer = null;
        answerController.clear();
        isAnswered = false;
        isCorrect = false;
      });
    } else {
      showResult();
    }
  }

  
  Future<void> saveQuizHistory() async {
    if (_sessionUserId == null || StudyStorage.currentUserId() != _sessionUserId) {
      throw StateError('풀이 중 로그인 사용자가 변경되었습니다.');
    }
    await StudyStorage.saveQuizResult(
      fileName: widget.fileName,
      answers: answerHistory,
      correctCount: correctCount,
      subjectId: widget.subjectId,
      semesterCode: widget.semesterCode,
      expectedUserId: _sessionUserId,
    );
  }
  
  Future<void> showResult() async {
    // 복습 결과를 휴대폰 내부 저장소에 저장
    try {
      await saveQuizHistory();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('복습 결과 저장에 실패했습니다: $e'),
        ),
      );
      return;
    }

    if (!mounted) return;

    // 기존 복습 완료 팝업 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('복습 완료!'),
        content: Text(
          '총 ${widget.questions.length}문제를 '
          '확인했습니다.\n\n'
          '객관식 정답 수: $correctCount개\n'
          '주관식은 모범답안으로 직접 확인해주세요.\n\n'
          '복습 결과가 저장되었습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('학습 노트로 돌아가기'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('복습 문제')),
        body: const Center(
          child: Text('생성된 문제가 없습니다.'),
        ),
      );
    }

    final question = widget.questions[currentIndex]
        as Map<String, dynamic>;

    final isMultipleChoice =
        question['type'] == 'multiple_choice';

    final options =
        (question['options'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 복습 퀴즈'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${currentIndex + 1} / '
                '${widget.questions.length} 문제',
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6759BC),
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              LinearProgressIndicator(
                value: (currentIndex + (isAnswered ? 1 : 0)) /
                    widget.questions.length,
                color: const Color(0xFF9185E8),
                backgroundColor: const Color(0xFFEAE6FA),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),

              const SizedBox(height: 32),

              Text(
                isMultipleChoice ? '객관식 문제' : '주관식 문제',
                style: const TextStyle(
                  color: Color(0xFF6759BC),
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                question['question'].toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              if (isMultipleChoice)
                RadioGroup<String>(
                  groupValue: selectedAnswer,
                  onChanged: (value) {
                    if (isAnswered) return;

                    setState(() {
                      selectedAnswer = value;
                    });
                  },
                  child: Column(
                    children: options.map<Widget>((option) {
                      return Card(
                        color: selectedAnswer == option
                            ? const Color(0xFFF1EEFF)
                            : null,
                        child: RadioListTile<String>(
                          title: Text(option),
                          value: option,
                          enabled: !isAnswered,
                          activeColor: const Color(0xFF9185E8),
                        ),
                      );
                    }).toList(),
                  ),
                )

              else
                TextField(
                  controller: answerController,
                  enabled: !isAnswered,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '정답을 입력해주세요.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              if (isAnswered) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EEFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      if (isMultipleChoice)
                        Text(
                          isCorrect ? '정답입니다!' : '오답입니다.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCorrect
                                ? Colors.green
                                : Colors.red,
                          ),
                        )
                      else
                        const Text(
                          '모범답안 확인',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      const SizedBox(height: 12),

                      Text(
                        '정답: ${question['answer']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        '해설: ${question['explanation']}',
                        style: const TextStyle(height: 1.6),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: nextQuestion,
                  child: Text(
                    currentIndex ==
                            widget.questions.length - 1
                        ? '학습 결과 확인'
                        : '다음 문제',
                  ),
                ),
              ] else
                ElevatedButton(
                  onPressed: checkAnswer,
                  child: const Text('정답 확인'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
