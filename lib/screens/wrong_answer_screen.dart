import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import 'wrong_answer_retry_screen.dart';


class WrongAnswerScreen extends StatefulWidget {
  final String? subjectId;
  final String? semesterCode;

  const WrongAnswerScreen({
    super.key,
    this.subjectId,
    this.semesterCode,
  });


  @override
  State<WrongAnswerScreen> createState() =>
      _WrongAnswerScreenState();
}

class _WrongAnswerScreenState extends State<WrongAnswerScreen> {
  late Future<List<Map<String, dynamic>>> wrongAnswersFuture;

    String formatStudyDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return '날짜 정보 없음';
    }

    final dateTime = DateTime.tryParse(value.toString());

    if (dateTime == null) {
      return '날짜 정보 없음';
    }

    final localTime = dateTime.toLocal();

    String twoDigits(int number) =>
        number.toString().padLeft(2, '0');

    return '${localTime.year}.'
        '${twoDigits(localTime.month)}.'
        '${twoDigits(localTime.day)} '
        '${twoDigits(localTime.hour)}:'
        '${twoDigits(localTime.minute)}';
  }

  @override
  void initState() {
    super.initState();
    wrongAnswersFuture = loadWrongAnswers();
  }

  // 저장된 복습 결과에서 오답만 추출
  Future<List<Map<String, dynamic>>> loadWrongAnswers() async {
    final results = await StudyStorage.loadQuizResults();

    final List<Map<String, dynamic>> wrongAnswers = [];

    for (final result in results) {
      // 과목과 학기가 전달된 경우 해당 기록만 조회
      if (widget.subjectId != null &&
          result['subjectId'] != widget.subjectId) {
        continue;
      }

      if (widget.semesterCode != null &&
          result['semesterCode'] != widget.semesterCode) {
        continue;
      }

      final answers = result['answers'] as List<dynamic>? ?? [];


      for (final item in answers) {
        final answer = Map<String, dynamic>.from(item as Map);

        // 객관식 오답만 추가
        if (answer['isCorrect'] == false) {
          wrongAnswers.add({
            ...answer,
            'fileName': result['fileName'] ?? '복습문제',
            'createdAt': result['createdAt'] ?? '',
          });
        }
      }
    }

    return wrongAnswers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오답 노트'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: wrongAnswersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('오답 기록을 불러오지 못했습니다.'),
              );
            }

            final wrongAnswers = snapshot.data ?? [];

            if (wrongAnswers.isEmpty) {
              return const Center(
                child: Text(
                  '저장된 오답이 없습니다.',
                  textAlign: TextAlign.center,
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: wrongAnswers.length,
              itemBuilder: (context, index) {
                final answer = wrongAnswers[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          '오답 ${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9185E8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          answer['question']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '내 답안: ${answer['userAnswer'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 6),                       
                        Text(
                        '정답: ${answer['correctAnswer'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.green,
                        ),
                        ),

                        // AI가 생성한 문제 해설
                        if ((answer['explanation']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),

                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FF),
                            borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                const Text(
                                'AI 문제 해설',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6F63B5),
                                ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                answer['explanation'].toString(),
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                ),
                                ),
                            ],
                            ),
                        ),
                        ],


                        const SizedBox(height: 12),
                        Text(
                          '학습 자료: ${answer['fileName']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '풀이 일시: ${formatStudyDateTime(answer['createdAt'])}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                                                
                        const SizedBox(height: 16),

                        // 객관식 보기가 저장된 문제만 다시 풀기 가능
                        if (answer['options'] is List &&
                            (answer['options'] as List).isNotEmpty)
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                            onPressed: () {
                                Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => WrongAnswerRetryScreen(
                                    question: answer,
                                    ),
                                ),
                                );
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('다시 풀기'),
                            ),
                        ),

                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
