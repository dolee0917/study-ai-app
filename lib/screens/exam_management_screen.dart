import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/study_storage.dart';
import 'recommended_review_screen.dart';
import 'exam_date_utils.dart';

class ExamManagementScreen extends StatefulWidget {
  const ExamManagementScreen({super.key});

  @override
  State<ExamManagementScreen> createState() =>
      _ExamManagementScreenState();
}

class ExamDeleteButton extends StatefulWidget {
  const ExamDeleteButton({super.key, required this.title, required this.delete});

  final String title;
  final Future<void> Function() delete;

  @override
  State<ExamDeleteButton> createState() => _ExamDeleteButtonState();
}

class _ExamDeleteButtonState extends State<ExamDeleteButton> {
  bool _busy = false;

  Future<void> _confirmDelete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('시험 일정 삭제'),
          content: Text('“${widget.title}” 일정을 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.delete();
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('시험 일정이 삭제되었습니다.')));
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('시험 일정을 삭제하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '시험 일정 삭제',
    onPressed: _busy ? null : _confirmDelete,
    icon: const Icon(Icons.delete_outline),
  );
}

class ExamReviewSummary extends StatefulWidget {
  const ExamReviewSummary({
    super.key,
    required this.weakStats,
    required this.availableCount,
    required this.daysUntilExam,
    required this.onStart,
    this.countForDifficulty,
    this.questionsForSettings,
    this.onStartCustom,
  });

  final Future<Map<String, dynamic>> weakStats;
  final Future<int> availableCount;
  final int? daysUntilExam;
  final Future<void> Function(int) onStart;
  final Future<int> Function(String)? countForDifficulty;
  final Future<List<Map<String, dynamic>>> Function(String, int)? questionsForSettings;
  final Future<void> Function(List<Map<String, dynamic>>)? onStartCustom;

  @override
  State<ExamReviewSummary> createState() => _ExamReviewSummaryState();
}

class _ExamReviewSummaryState extends State<ExamReviewSummary> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<Map<String, dynamic>>(
          key: ObjectKey(widget.weakStats),
          future: widget.weakStats,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Text('취약 문제 분석 중...');
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Text('취약 문제 분석을 불러오지 못했습니다.');
            }
            final remaining = snapshot.data!['remainingWeakCount'] as int;
            final rate = snapshot.data!['resolutionRate'] as num;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('남은 취약 문제: $remaining개'),
                const SizedBox(height: 4),
                Text('취약 문제 해소율: ${rate.toStringAsFixed(1)}%'),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        FutureBuilder<int>(
          key: ObjectKey(widget.availableCount),
          future: widget.availableCount,
          builder: (context, snapshot) {
            final days = widget.daysUntilExam;
            final available = snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError ? snapshot.data : null;
            final count = days == null || available == null ? 0 :
                StudyStorage.calculateTodayRecommendedCount(
                  availableQuestionCount: available, daysUntilExam: days,
                );
            final String text;
            if (days == null) {
              text = '시험 날짜를 확인할 수 없습니다.';
            } else if (days < 0) {
              text = '종료된 시험입니다.';
            } else if (snapshot.connectionState != ConnectionState.done) {
              text = '추천 문제를 불러오는 중...';
            } else if (snapshot.hasError || available == null) {
              text = '추천 문제를 불러오지 못했습니다.';
            } else {
              text = count == 0 ? '복습할 문제가 없습니다.' : '오늘의 추천 복습: $count문제';
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: count == 0 || _starting ? null : () async {
                    setState(() => _starting = true);
                    try {
                       final selection = await showDialog<ReviewSettingsResult>(
                         context: context,
                         builder: (_) => ReviewSettingsDialog(
                           initialCount: count,
                           countForDifficulty: widget.countForDifficulty ?? ((_) async => available!),
                            questionsForSettings: widget.questionsForSettings,
                         ),
                       );
                       if (selection != null && mounted) {
                         if (selection.automatic) {
                           await widget.onStart(available!);
                         } else if (selection.questions != null) {
                           await widget.onStartCustom?.call(selection.questions!);
                         }
                       }
                    } finally {
                      if (mounted) setState(() => _starting = false);
                    }
                  },
                  child: const Text('추천 복습 시작하기'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ReviewSettingsResult {
  const ReviewSettingsResult.automatic() : automatic = true, questions = null;
  const ReviewSettingsResult.custom(this.questions) : automatic = false;
  final bool automatic;
  final List<Map<String, dynamic>>? questions;
}

class ReviewSettingsDialog extends StatefulWidget {
  const ReviewSettingsDialog({super.key, required this.initialCount,
    required this.countForDifficulty, this.questionsForSettings});

  final int initialCount;
  final Future<int> Function(String) countForDifficulty;
  final Future<List<Map<String, dynamic>>> Function(String, int)? questionsForSettings;

  @override
  State<ReviewSettingsDialog> createState() => _ReviewSettingsDialogState();
}

class _ReviewSettingsDialogState extends State<ReviewSettingsDialog> {
  String _difficulty = 'all';
  late int _count;
  late Future<int> _available;
  bool _starting = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount.clamp(1, StudyStorage.maxCustomReviewQuestionCount).toInt();
    _loadCount();
  }

  void _loadCount() {
    _available = Future.sync(() => widget.countForDifficulty(_difficulty));
  }

  Future<void> _startCustom() async {
    if (_starting || widget.questionsForSettings == null) return;
    setState(() { _starting = true; _startError = null; });
    try {
      final questions = await widget.questionsForSettings!(_difficulty, _count);
      if (!mounted) return;
      if (questions.isEmpty) {
        setState(() { _startError = '복습 가능한 문제가 없습니다. 조건을 변경해 주세요.'; _loadCount(); });
        return;
      }
      if (questions.length < _count) {
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: const Text('복습 문제 수 확인'),
          content: Text('요청한 $_count문제 중 현재 ${questions.length}문제를 풀 수 있습니다. 이 문제들로 시작할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('조건 변경')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('시작하기')),
          ],
        ));
        if (!mounted || confirmed != true) return;
      }
      if (mounted) Navigator.pop(context, ReviewSettingsResult.custom(questions));
    } catch (_) {
      if (mounted) setState(() => _startError = '추천 문제를 불러오지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('맞춤 복습 설정'),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _difficulty,
          decoration: const InputDecoration(labelText: '난이도'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('전체')),
            DropdownMenuItem(value: 'easy', child: Text('쉬움')),
            DropdownMenuItem(value: 'medium', child: Text('보통')),
            DropdownMenuItem(value: 'hard', child: Text('어려움')),
          ],
          onChanged: _starting ? null : (value) {
            if (value == null || value == _difficulty) return;
            setState(() { _difficulty = value; _loadCount(); });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _count,
          decoration: const InputDecoration(labelText: '문제 개수'),
          items: List.generate(StudyStorage.maxCustomReviewQuestionCount,
            (index) => DropdownMenuItem(value: index + 1, child: Text('${index + 1}개'))),
          onChanged: _starting ? null : (value) { if (value != null) setState(() => _count = value); },
        ),
        const SizedBox(height: 16),
        FutureBuilder<int>(
          key: ObjectKey(_available), future: _available,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Text('추천 가능 문제를 확인하는 중...');
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Text('추천 가능 문제 수를 불러오지 못했습니다.');
            }
            final available = snapshot.data!;
            if (available == 0) return const Text('선택한 난이도에 복습 가능한 문제가 없습니다.');
            if (available < _count) {
              return Text('추천 가능: $available문제 · 요청한 $_count문제보다 부족합니다.');
            }
            return Text('추천 가능: $available문제');
          },
        ),
        if (_startError != null) ...[
          const SizedBox(height: 12),
          Text(_startError!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    )),
    actions: [
      TextButton(onPressed: _starting ? null : () => Navigator.pop(context), child: const Text('닫기')),
      ElevatedButton(onPressed: _starting ? null : () => Navigator.pop(context, const ReviewSettingsResult.automatic()),
        child: const Text('기존 추천 복습 시작')),
      FutureBuilder<int>(
        key: ObjectKey(_available), future: _available,
        builder: (context, snapshot) => ElevatedButton(
          onPressed: _starting || widget.questionsForSettings == null ||
              snapshot.connectionState != ConnectionState.done || snapshot.hasError ||
              (snapshot.data ?? 0) <= 0 ? null : _startCustom,
          child: Text(_starting ? '문제 확인 중...' : '맞춤 복습 시작'),
        ),
      ),
    ],
  );
}

class _ExamManagementScreenState extends State<ExamManagementScreen> {
  static const Color _lavender = Color(0xFF8576D8);
  static const Color _ink = Color(0xFF242B50);

  
  int _selectedYear = DateTime.now().year;
  int _selectedSemester = DateTime.now().month <= 6 ? 1 : 2;
  String get _selectedSemesterCode => '$_selectedYear-$_selectedSemester';

  final Map<String, Future<String>> _subjectNames = {};

  final Map<String, Future<Map<String, dynamic>>> _weakStats = {};
  final Map<String, Future<int>> _reviewCounts = {};

  Future<Map<String, dynamic>>? _subjectWeakStats(
    String uid,
    String? semesterCode,
    String? subjectId,
  ) {
    if (semesterCode == null || semesterCode.trim().isEmpty ||
        subjectId == null || subjectId.trim().isEmpty ||
        semesterCode.contains('/') || subjectId.contains('/')) {
      return null;
    }
    final key = '$uid/$semesterCode/$subjectId';
    return _weakStats.putIfAbsent(
      key,
      () => StudyStorage.getSubjectWeakQuestionStats(
        semesterCode: semesterCode,
        subjectId: subjectId,
      ),
    );
  }

  Future<int>? _subjectReviewCount(
    String uid, String? semesterCode, String? subjectId,
  ) {
    if (semesterCode == null || semesterCode.trim().isEmpty ||
        subjectId == null || subjectId.trim().isEmpty ||
        semesterCode.contains('/') || subjectId.contains('/')) {
      return null;
    }
    final key = '$uid/$semesterCode/$subjectId';
    return _reviewCounts.putIfAbsent(key, () =>
      StudyStorage.getRecommendedReviewQuestionCount(
        semesterCode: semesterCode, subjectId: subjectId,
      ));
  }

  String _semesterText(String? code) {
    final match = code == null ? null : RegExp(r'^(\d{4})-([12])$').firstMatch(code);
    if (match == null) return '학기 정보 없음';
    return '${match.group(1)}년 ${match.group(2)}학기';
  }

  Future<String> _subjectName(String uid, String? semesterCode, String? subjectId) {
    if (semesterCode == null || semesterCode.isEmpty ||
        subjectId == null || subjectId.isEmpty ||
        semesterCode.contains('/') || subjectId.contains('/')) {
      return Future.value('과목 정보 없음');
    }
    final key = '$uid/$semesterCode/$subjectId';
    return _subjectNames.putIfAbsent(key, () async {
      try {
        final subject = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('semesters')
            .doc(semesterCode)
            .collection('subjects')
            .doc(subjectId)
            .get();
        final name = subject.data()?['name'];
        if (name is! String || name.trim().isEmpty) {
          return '과목 정보 없음';
        }
        return name;
      } catch (_) {
        return '과목 조회 실패';
      }
    });
  }

  int? _daysUntilExam(DateTime? examDate) {
    return daysUntilExam(examDate);
  }

  String? _dDayText(int? days) {
    return examDDayText(days);
  }

  Future<void> _showAddExamDialog() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final titleController = TextEditingController();
    DateTime? selectedDate;
    String? selectedSubjectId;
    final selectedSemesterCode = _selectedSemesterCode;

    try {
        final subjectOptions = <Map<String, String>>[];

        final currentYear = DateTime.now().year;

        // 기존 과목 관리 화면에서 사용하는 학년도 범위
        final years = List.generate(
        11,
        (index) => currentYear - 5 + index,
        );

        for (final year in years) {
        for (final semester in [1, 2]) {
            final semesterCode = '$year-$semester';

            final subjects = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('semesters')
                .doc(semesterCode)
                .collection('subjects')
                .get();

            for (final subject in subjects.docs) {
            subjectOptions.add({
                'subjectId': subject.id,
                'semesterCode': semesterCode,
                'name': subject.data()['name']?.toString() ?? '이름 없음',
            });
            }
        }
        }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('시험 일정 추가'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        maxLength: 50,
                        decoration: const InputDecoration(
                          labelText: '시험 제목',
                          hintText: '예: 운영체제 기말고사',
                          border: OutlineInputBorder(),
                        ),
                      ),
                        
                        const SizedBox(height: 12),

                      
                        // 선택한 학기의 수강 과목만 표시
                        DropdownButtonFormField<String>(
                        key: ValueKey(selectedSemesterCode),
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: '수강 과목',
                            border: OutlineInputBorder(),
                        ),
                        hint: Text('수강 과목을 선택해주세요'),
                        items: subjectOptions
                            .where(
                                (subject) =>
                                    subject['semesterCode'] == selectedSemesterCode,
                            )
                            .map((subject) {
                                return DropdownMenuItem<String>(
                                value: subject['subjectId']!,
                                child: Text(
                                    subject['name']!,
                                    overflow: TextOverflow.ellipsis,
                                ),
                                );
                            })
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSubjectId = value;
                          });
                        },
                        ),

                      if (subjectOptions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '등록된 과목이 없습니다. 먼저 수강 과목을 등록해주세요.',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );

                          if (date != null) {
                            setDialogState(() {
                              selectedDate = date;
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          selectedDate == null
                              ? '시험 날짜 선택'
                              : '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('취소'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty ||
                          selectedSubjectId == null ||
                          selectedDate == null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('모든 항목을 입력해주세요.'),
                          ),
                        );
                        return;
                      }

                      
                      try {
                        final examsRef = FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('exams');

                        await examsRef.add({
                          'title': titleController.text.trim(),
                          'examDate': Timestamp.fromDate(selectedDate!),
                          'subjectId': selectedSubjectId,
                          'semesterCode': selectedSemesterCode,
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        if (!mounted || !dialogContext.mounted) return;

                        Navigator.pop(dialogContext);

                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('시험 일정이 저장되었습니다.'),
                          ),
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;

                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('시험 일정 저장 실패: $e'),
                          ),
                        );
                      }

                    },
                    child: const Text('등록'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('과목 목록 조회 실패: $e')),
      );
    } finally {
      // 다이얼로그 전환 애니메이션 중 컨트롤러가 참조될 수 있으므로
      // 프레임 종료 후 정리합니다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      appBar: AppBar(
        title: const Text(
          '시험 일정 관리',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _ink,
          ),
        ),
        backgroundColor: const Color(0xFFF9F9FF),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '나의 시험 일정',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '시험 일정을 등록하고 과목별 복습 계획을 관리해요.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF66708F),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    decoration: const InputDecoration(
                      labelText: '학년도',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(11, (index) => DateTime.now().year - 5 + index)
                        .map((year) => DropdownMenuItem(
                              value: year,
                              child: Text('$year년'),
                            ))
                        .toList(),
                    onChanged: (year) {
                      if (year == null || year == _selectedYear) return;
                      setState(() {
                        _selectedYear = year;
                        _selectedSemester = DateTime.now().month <= 6 ? 1 : 2;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('semester-$_selectedYear-$_selectedSemester'),
                    initialValue: _selectedSemester,
                    decoration: const InputDecoration(
                      labelText: '학기',
                      border: OutlineInputBorder(),
                    ),
                    items: [1, 2]
                        .map((semester) => DropdownMenuItem(
                              value: semester,
                              child: Text('$semester학기'),
                            ))
                        .toList(),
                    onChanged: (semester) {
                      if (semester == null || semester == _selectedSemester) return;
                      setState(() {
                        _selectedSemester = semester;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _showAddExamDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _lavender,
                  foregroundColor: Colors.white,
                ),
                child: const Text('+ 시험 일정 추가하기'),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
            child: Builder(
                builder: (context) {
                final user = FirebaseAuth.instance.currentUser;

                if (user == null) {
                    return const Center(
                    child: Text('로그인이 필요합니다.'),
                    );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('exams')
                        .orderBy('examDate')
                        .snapshots(),
                    builder: (context, snapshot) {
                    if (snapshot.hasError) {
                        return const Center(
                        child: Text('시험 일정을 불러오지 못했습니다.'),
                        );
                    }

                    if (!snapshot.hasData) {
                        return const Center(
                        child: CircularProgressIndicator(),
                        );
                    }

                    final exams = snapshot.data!.docs.where((exam) {
                      final data = exam.data();
                      return data['semesterCode'] == _selectedSemesterCode;
                    }).toList();

                    if (exams.isEmpty) {
                      return const Center(
                        child: Text('선택한 조건에 등록된 시험 일정이 없습니다.'),
                      );
                    }

                    return ListView.builder(
                        itemCount: exams.length,
                        itemBuilder: (context, index) {
                        final exam = exams[index];
                        final data = exam.data();

                        final title =
                            data['title']?.toString() ?? '시험 제목 없음';

                        final semesterCode = data['semesterCode'] is String
                            ? data['semesterCode'] as String
                            : null;
                        final subjectId = data['subjectId'] is String
                            ? data['subjectId'] as String
                            : null;
                        final subjectName = _subjectName(
                          user.uid, semesterCode, subjectId,
                        );
                        final weakStats = _subjectWeakStats(
                          user.uid, semesterCode, subjectId,
                        );
                        final reviewCount = _subjectReviewCount(
                          user.uid, semesterCode, subjectId,
                        );

                        final timestamp = data['examDate'];

                        DateTime? examDate;
                        if (timestamp is Timestamp) {
                          try {
                            examDate = timestamp.toDate().toLocal();
                          } catch (_) {
                            // Treat malformed dates as unavailable.
                          }
                        }
                        final daysUntilExam = _daysUntilExam(examDate);
                        final dDayText = _dDayText(daysUntilExam);

                        final dateText = examDate == null
                            ? '날짜 정보 없음'
                            : '${examDate.year}-'
                                '${examDate.month.toString().padLeft(2, '0')}-'
                                '${examDate.day.toString().padLeft(2, '0')}';

                        return Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                            ),
                            leading: const Icon(
                                Icons.event_note_rounded,
                                color: _lavender,
                                size: 30,
                            ),
                            title: Text(
                                title,
                                style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _ink,
                                ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (dDayText != null) Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0EDFF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      dDayText,
                                      style: const TextStyle(
                                        color: _lavender,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ExamDeleteButton(
                                  key: ValueKey('${user.uid}/${exam.id}'),
                                  title: title,
                                  delete: () async {
                                    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
                                      throw StateError('User has changed');
                                    }
                                    await exam.reference.delete();
                                  },
                                ),
                              ],
                            ),
                            subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('시험 날짜: $dateText'),
                                    const SizedBox(height: 4),
                                    FutureBuilder<String>(
                                      future: subjectName,
                                      builder: (context, snapshot) => Text(
                                        '${_semesterText(semesterCode)} · '
                                        '${snapshot.data ?? "과목 조회 중..."}',
                                      ),
                                    ),
                                  ],
                                ),
                            ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: weakStats == null || reviewCount == null ||
                                      semesterCode == null || subjectId == null
                                  ? const Text('취약 문제 분석을 위한 과목 정보가 없습니다.')
                                  : ExamReviewSummary(
                                      weakStats: weakStats,
                                      availableCount: reviewCount,
                                      daysUntilExam: daysUntilExam,
                                      countForDifficulty: (difficulty) =>
                                          StudyStorage.getRecommendedReviewQuestionCount(
                                            semesterCode: semesterCode,
                                            subjectId: subjectId,
                                            difficulty: difficulty,
                                          ),
                                      questionsForSettings: (String difficulty, int count) =>
                                          StudyStorage.getRecommendedReviewQuestions(
                                            semesterCode: semesterCode, subjectId: subjectId,
                                            difficulty: difficulty, limit: count,
                                          ),
                                      onStartCustom: (questions) async {
                                        final currentDays = _daysUntilExam(examDate);
                                        if (currentDays == null || currentDays < 0) {
                                          setState(() {});
                                          return;
                                        }
                                        await Navigator.of(context).push(MaterialPageRoute<void>(
                                          builder: (_) => RecommendedReviewScreen(
                                            semesterCode: semesterCode, subjectId: subjectId,
                                            count: questions.length, questions: questions,
                                          ),
                                        ));
                                        if (!mounted) return;
                                        setState(() {
                                          final key = '${user.uid}/$semesterCode/$subjectId';
                                          _weakStats.remove(key);
                                          _reviewCounts.remove(key);
                                        });
                                      },
                                      onStart: (available) async {
                                        final currentDays = _daysUntilExam(examDate);
                                        if (currentDays == null || currentDays < 0) {
                                          setState(() {});
                                          return;
                                        }
                                        final currentCount = StudyStorage.calculateTodayRecommendedCount(
                                          availableQuestionCount: available,
                                          daysUntilExam: currentDays,
                                        );
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => RecommendedReviewScreen(
                                              semesterCode: semesterCode,
                                              subjectId: subjectId,
                                              count: currentCount,
                                            ),
                                          ),
                                        );
                                        if (!mounted) return;
                                        setState(() {
                                          final key = '${user.uid}/$semesterCode/$subjectId';
                                          _weakStats.remove(key);
                                          _reviewCounts.remove(key);
                                        });
                                      },
                                    ),
                            ),
                            ],
                            ),
                        );
                        },
                    );
                    },
                );
                },
            ),
            ),

          ],
        ),
      ),
    );
  }
}
