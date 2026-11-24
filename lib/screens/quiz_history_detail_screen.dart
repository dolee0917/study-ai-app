import 'package:flutter/material.dart';
import 'quiz_screen.dart';

List<Map<String, dynamic>> restoreQuizQuestions(
  List<dynamic> answers,
) {
  return answers.map((item) {
    final answer = Map<String, dynamic>.from(item as Map);

    final options = answer['options'];

    final savedType = answer['type']?.toString();

    final type = savedType == 'multiple_choice' ||
            savedType == 'short_answer'
        ? savedType!
        : options is List && options.isNotEmpty
            ? 'multiple_choice'
            : 'short_answer';

    return <String, dynamic>{
      'question': answer['question']?.toString() ?? '',
      'type': type,
      'options': options is List ? List<dynamic>.from(options) : [],
      'answer': answer['correctAnswer']?.toString() ?? '',
      'explanation': answer['explanation']?.toString() ?? '',
      for (final key in ['questionId', 'noteId', 'concept', 'subConcept', 'difficulty'])
        if (answer.containsKey(key)) key: answer[key],
    };
  }).toList();
}

class QuizHistoryDetailScreen extends StatelessWidget {
  const QuizHistoryDetailScreen({
    super.key,
    required this.result,
  });

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final fileName =
        result['fileName']?.toString() ?? '복습 문제';

    final answers =
        (result['answers'] as List<dynamic>? ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('문제 풀이 상세 기록'),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
            onPressed: answers.isEmpty
                ? null
                : () {
                    final questions = restoreQuizQuestions(answers);

                    Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QuizScreen(
                        questions: questions,
                        fileName:
                            result['fileName']?.toString() ?? '복습 문제',
                        subjectId: result['subjectId'] as String?,
                        semesterCode: result['semesterCode'] as String?,
                        ),
                    ),
                    );
                },
            icon: const Icon(Icons.replay),
            label: const Text('전체 문제 다시 풀기'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            ),
        ),
        ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              fileName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: answers.isEmpty
                ? const Center(
                    child: Text('저장된 문제 기록이 없습니다.'),
                    )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: answers.length,
                    itemBuilder: (context, index) {
                        final answer = Map<String, dynamic>.from(
                        answers[index] as Map,
                        );

                        final question =
                            answer['question']?.toString() ?? '문제 내용 없음';

                        final userAnswer =
                            answer['userAnswer']?.toString() ?? '답안 없음';

                        final correctAnswer =
                            answer['correctAnswer']?.toString() ?? '정답 정보 없음';

                        final explanation =
                            answer['explanation']?.toString() ?? '';

                        final bool? isCorrect = answer['isCorrect'] is bool
                            ? answer['isCorrect'] as bool
                            : null;

                        return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                '문제 ${index + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8576D8),
                                ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                question,
                                style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 16),

                                Text(
                                '내가 제출한 답: $userAnswer',
                                style: const TextStyle(fontSize: 14),
                                ),

                                const SizedBox(height: 8),

                                Text(
                                '정답: $correctAnswer',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                ),
                                ),

                                const SizedBox(height: 8),

                                if (isCorrect != null)
                                Row(
                                    children: [
                                    Icon(
                                        isCorrect ? Icons.check_circle : Icons.cancel,
                                        color: isCorrect ? Colors.green : Colors.red,
                                        size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                        isCorrect ? '정답입니다.' : '오답입니다.',
                                    ),
                                    ],
                                ),

                                if (isCorrect == null)
                                const Text(
                                    '주관식 문제: 모범답안과 비교해 주세요.',
                                    style: TextStyle(color: Colors.grey),
                                ),

                                if (explanation.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                    '문제 해설',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(explanation),
                                ],
                            ],
                            ),
                        ),
                        );
                    },
                    ),
            ),
        ],
      ),
    );
  }
}
