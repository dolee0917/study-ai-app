import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import 'study_note_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'wrong_answer_screen.dart';
import 'quiz_history_detail_screen.dart';

class StudyHistoryScreen extends StatefulWidget {
  const StudyHistoryScreen({super.key});

  @override
  State<StudyHistoryScreen> createState() =>
      _StudyHistoryScreenState();
}


class _StudyHistoryScreenState
    extends State<StudyHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _notesFuture;
  late Future<List<Map<String, dynamic>>> _quizResultsFuture;

  // 현재 선택한 학년도
  int selectedYear = DateTime.now().year;

  // 현재 선택한 학기
  String selectedSemester =
      DateTime.now().month <= 6 ? '1학기' : '2학기';

  // 학기별 데이터 조회에 사용할 코드
  String get selectedSemesterCode =>
      '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

  // 선택한 과목 ID
  String? selectedSubjectId;


  Stream<QuerySnapshot<Map<String, dynamic>>> get subjectsStream {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('semesters')
        .doc(selectedSemesterCode)
        .collection('subjects')
        .snapshots();
  }
  
@override
void initState() {
  super.initState();
  _refreshNotes();
  _refreshQuizResults();
}


  void _refreshNotes() {
    _notesFuture = StudyStorage.loadNotes();
  }

  void _refreshQuizResults() {
    _quizResultsFuture = StudyStorage.loadQuizResults();
  }

  Future<void> _refreshAllRecords() async {
    setState(() {
      _refreshNotes();
      _refreshQuizResults();
    });

    await Future.wait([
      _notesFuture,
      _quizResultsFuture,
    ]);
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyNoteScreen(
          fileName: note['fileName'] as String,
          summaryText: note['summaryText'] as String,
          originalText: note['originalText'] as String,
          isFromHistory: true,
          subjectId: note['subjectId'] as String?,
          semesterCode: note['semesterCode'] as String?,
        ),
      ),
    );

    if (!mounted) return;

    await _refreshAllRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      title: const Text('학습 기록'),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '학습 기록 새로고침',
          onPressed: _refreshAllRecords,
        ),
      ],
    ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('year-$selectedYear'),
                    initialValue: selectedYear,
                    decoration: const InputDecoration(
                      labelText: '학년도',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      6,
                      (index) => DateTime.now().year - index,
                    ).map((year) => DropdownMenuItem<int>(
                      value: year,
                      child: Text('$year년'),
                    )).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedYear = value;
                        selectedSubjectId = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('semester-$selectedSemester'),
                    initialValue: selectedSemester,
                    decoration: const InputDecoration(
                      labelText: '학기',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '1학기', child: Text('1학기')),
                      DropdownMenuItem(value: '2학기', child: Text('2학기')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedSemester = value;
                        selectedSubjectId = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: subjectsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('과목 목록을 불러오지 못했습니다.');
                }

                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }

                final subjects = snapshot.data!.docs;

                if (subjects.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('선택한 학기에 등록된 과목이 없습니다.'),
                  );
                }

                final validSubjectId =
                    subjects.any((subject) => subject.id == selectedSubjectId)
                        ? selectedSubjectId
                        : null;

                return DropdownButtonFormField<String>(
                  key: ValueKey(selectedSemesterCode),
                  initialValue: validSubjectId,
                  decoration: const InputDecoration(
                    labelText: '과목 선택',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('과목을 선택해주세요'),
                  isExpanded: true,
                  items: subjects.map((subject) {
                    final name = subject.data()['name']?.toString() ?? '이름 없는 과목';

                    return DropdownMenuItem<String>(
                      value: subject.id,
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedSubjectId = value;
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),


          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: selectedSubjectId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WrongAnswerScreen(
                              subjectId: selectedSubjectId,
                              semesterCode: selectedSemesterCode,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('선택한 과목의 오답 노트'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '복습 문제 풀이 기록',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _quizResultsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(child: Text('풀이 기록을 불러오지 못했습니다.'));
                }

                if (selectedSubjectId == null) {
                  return const Center(child: Text('과목을 선택해주세요.'));
                }

                final results = (snapshot.data ?? <Map<String, dynamic>>[])
                    .where((result) =>
                        result['subjectId'] == selectedSubjectId &&
                        result['semesterCode'] == selectedSemesterCode)
                    .toList();

                if (results.isEmpty) {
                  return const Center(child: Text('해당 과목의 풀이 기록이 없습니다.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    final fileName = result['fileName']?.toString() ?? '복습 문제';
                    final correctCount = result['correctCount'] ?? 0;
                    final totalQuestions = result['totalQuestions'] ?? 0;
                    final createdAt = result['createdAt']?.toString() ?? '';
                    final date = createdAt.length >= 10
                        ? createdAt.substring(0, 10)
                        : createdAt;

                    return Card(
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuizHistoryDetailScreen(
                                result: result,
                              ),
                            ),
                          );
                        },
                        leading: const Icon(Icons.assignment_turned_in_outlined),
                        title: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '객관식 정답: $correctCount개 / 전체: $totalQuestions문제\n'
                          '풀이 날짜: $date',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),


          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '학습 기록을 불러오지 못했습니다.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }
          
          final allNotes = snapshot.data ?? <Map<String, dynamic>>[];

          final notes = allNotes.where((note) {
            return note['semesterCode'] == selectedSemesterCode &&
                note['subjectId'] == selectedSubjectId;
          }).toList();

          if (selectedSubjectId == null) {
            return const Center(
              child: Text(
                '학습 기록을 확인할 과목을 선택해주세요.',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (notes.isEmpty) {

            return const Center(
              child: Text(
                '저장된 학습 노트가 없습니다.\n'
                '강의자료를 업로드하고 AI 학습 노트를 저장해주세요.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final fileName =
                  note['fileName']?.toString() ?? '강의자료';

              final date =
                  note['createdAt']?.toString() ?? '';

              final displayDate = date.length >= 10
                  ? date.substring(0, 10)
                  : date;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(
                    Icons.menu_book,
                    color: Color(0xFF9185E8),
                  ),
                  title: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('저장 날짜: $displayDate'),
                  trailing:
                      const Icon(Icons.chevron_right),
                  onTap: () => _openNote(note),
                ),
              );
            },
          );
              },
            ),
          ),
        ],
      
      ),
    );
  }
}
