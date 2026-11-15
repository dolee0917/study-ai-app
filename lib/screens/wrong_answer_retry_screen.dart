import 'package:flutter/material.dart';

class WrongAnswerRetryScreen extends StatefulWidget {
  final Map<String, dynamic> question;

  const WrongAnswerRetryScreen({
    super.key,
    required this.question,
  });

  @override
  State<WrongAnswerRetryScreen> createState() =>
      _WrongAnswerRetryScreenState();
}

class _WrongAnswerRetryScreenState
    extends State<WrongAnswerRetryScreen> {
  String? selectedAnswer;
  bool isAnswered = false;
  bool isCorrect = false;

  void checkAnswer() {
    if (selectedAnswer == null || isAnswered) return;

    final correctAnswer =
        widget.question['correctAnswer'].toString().trim();

    setState(() {
      isAnswered = true;
      isCorrect = selectedAnswer!.trim() == correctAnswer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;

    final options =
        question['options'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('오답 다시 풀기'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '다시 도전해보세요!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6F63B5),
                ),
              ),

              const SizedBox(height: 24),

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
                  if (isAnswered) return;

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
                      enabled: !isAnswered,
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isAnswered ? null : checkAnswer,
                  child: const Text('정답 확인하기'),
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
                      Navigator.pop(context);
                    },
                    child: const Text('오답 노트로 돌아가기'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
