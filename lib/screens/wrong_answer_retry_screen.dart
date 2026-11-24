import 'package:flutter/material.dart';
import '../services/study_storage.dart';

class WrongAnswerRetryScreen extends StatefulWidget {
  final Map<String, dynamic> question;
  final int? currentNumber;
  final int? totalCount;
  final VoidCallback? onCompleted;
  final ValueChanged<bool>? onAnswerSaved;
  final bool isRecommendedReview;

  const WrongAnswerRetryScreen({
    super.key,
    required this.question,
    this.currentNumber,
    this.totalCount,
    this.onCompleted,
    this.onAnswerSaved,
    this.isRecommendedReview = false,
  });

  @override
  State<WrongAnswerRetryScreen> createState() =>
      _WrongAnswerRetryScreenState();
}

class _WrongAnswerRetryScreenState
    extends State<WrongAnswerRetryScreen> {
  late final String? _sessionUserId;
  String? selectedAnswer;
  bool isAnswered = false;
  bool isCorrect = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _sessionUserId = StudyStorage.currentUserId();
  }

  
  Future<void> checkAnswer() async {
    if (selectedAnswer == null || isAnswered || isSaving) return;

    final correctAnswer =
        widget.question['correctAnswer'].toString().trim();

    final result = selectedAnswer!.trim() == correctAnswer;

    setState(() {
      isSaving = true;
    });

    try {
      if (_sessionUserId == null || StudyStorage.currentUserId() != _sessionUserId) {
        throw StateError('풀이 중 로그인 사용자가 변경되었습니다.');
      }
      await StudyStorage.saveRetryResult(
        question: widget.question['question']?.toString() ?? '',
        userAnswer: selectedAnswer!,
        correctAnswer: correctAnswer,
        isCorrect: result,
        reviewType: widget.isRecommendedReview
            ? 'recommended_review'
            : 'wrong_answer_retry',
        subjectId: widget.question['subjectId']?.toString(),
        semesterCode: widget.question['semesterCode']?.toString(),
        fileName: widget.question['fileName']?.toString(),
        questionMetadata: widget.question,
        expectedUserId: _sessionUserId,
      );
      if (!mounted) return;
      setState(() {
        isAnswered = true;
        isCorrect = result;
      });
      widget.onAnswerSaved?.call(result);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('재풀이 결과를 저장하지 못했습니다.'),
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final question = widget.question;

    final options =
        question['options'] as List<dynamic>? ?? [];
    final currentNumber = widget.currentNumber ?? 1;
    final totalCount = widget.totalCount ?? 1;

    return PopScope(
      canPop: !isSaving,
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.isRecommendedReview ? '오늘의 추천 복습' : '오답 다시 풀기'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isRecommendedReview
                    ? '오늘의 추천 문제를 풀어보세요!'
                    : '다시 도전해보세요!',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6F63B5),
                ),
              ),

              const SizedBox(height: 24),

              Text('$currentNumber / $totalCount'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: totalCount > 0
                    ? ((currentNumber - 1 + (isAnswered ? 1 : 0)) / totalCount)
                        .clamp(0.0, 1.0)
                    : 0.0,
                color: const Color(0xFF9185E8),
                backgroundColor: const Color(0xFFEAE6FA),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 16),

              Text(
                question['question']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 20),

              // 객관식 보기 표시
              RadioGroup<String>(
                groupValue: selectedAnswer,
                onChanged: (value) {
                  if (isAnswered || isSaving) return;

                  setState(() {
                    selectedAnswer = value;
                  });
                },
                child: Column(
                  children: options.map<Widget>((option) {
                    final optionText = option.toString();

                    return RadioListTile<String>(
                      title: Text(optionText),
                      value: optionText,
                      enabled: !isAnswered && !isSaving,
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isAnswered || isSaving ? null : checkAnswer,
                  child: Text(isSaving ? '저장 중...' : '정답 확인하기'),
                ),
              ),

              if (isAnswered) ...[
                const SizedBox(height: 24),

                Text(
                  isCorrect
                      ? '정답입니다!'
                      : '아쉽지만 오답입니다.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isCorrect
                        ? Colors.green
                        : Colors.redAccent,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  '정답: ${question['correctAnswer']}',
                ),

                const SizedBox(height: 16),

                if ((question['explanation']
                            ?.toString() ?? '')
                        .isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FF),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI 문제 해설',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6F63B5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          question['explanation']
                                  ?.toString() ??
                              '',
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      if (widget.onCompleted != null) {
                        widget.onCompleted!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(widget.onCompleted == null
                        ? '오답 노트로 돌아가기'
                        : widget.currentNumber == widget.totalCount ? '복습 완료' : '다음 문제'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
