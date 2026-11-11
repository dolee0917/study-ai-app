import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class SubjectManagementScreen extends StatefulWidget {
  const SubjectManagementScreen({super.key});

  @override
  State<SubjectManagementScreen> createState() =>
      _SubjectManagementScreenState();
}

class _SubjectManagementScreenState
    extends State<SubjectManagementScreen> {
  int selectedYear = DateTime.now().year;
  String selectedSemester =
      DateTime.now().month <= 6 ? '1학기' : '2학기';


Future<void> deleteSubject(
  String subjectId,
  String subjectName,
) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return;

  final semesterCode =
      '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('수강 과목 삭제'),
        content: Text(
          '$subjectName 과목을 삭제하시겠습니까?\n'
          '삭제한 과목은 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      );
    },
  );

  if (!mounted || shouldDelete != true) return;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('semesters')
        .doc(semesterCode)
        .collection('subjects')
        .doc(subjectId)
        .delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$subjectName 과목이 삭제되었습니다.'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('과목 삭제 실패: $e'),
      ),
    );
  }
}



Future<void> editSubject(
  String subjectId,
  String currentName,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final semesterCode =
      '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

  final subjectRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('semesters')
      .doc(semesterCode)
      .collection('subjects')
      .doc(subjectId);

  final newName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      String inputName = currentName;

      return AlertDialog(
        title: const Text('수강 과목 수정'),
        content: TextFormField(
          initialValue: currentName,
          maxLength: 50,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '과목명',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            inputName = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = inputName.trim();

              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(
                  const SnackBar(
                    content: Text('과목명을 입력해주세요.'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext, name);
            },
            child: const Text('저장'),
          ),
        ],
      );
    },
  );

  
    if (!mounted || newName == null) return;

    final normalizedName = newName.trim().toLowerCase();
    final normalizedCurrentName = currentName.trim().toLowerCase();

    if (normalizedName == normalizedCurrentName) return;

    try {
    final existingSubjects = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('semesters')
        .doc(semesterCode)
        .collection('subjects')
        .get();

    final isDuplicate = existingSubjects.docs.any((doc) {
        if (doc.id == subjectId) return false;

        final existingName =
            (doc.data()['name'] as String? ?? '')
                .trim()
                .toLowerCase();

        return existingName == normalizedName;
    });

    if (isDuplicate) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$newName 과목은 이미 등록되어 있습니다.'),
        ),
        );
        return;
    }

    await subjectRef.update({

      'name': newName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('과목명이 $newName(으)로 수정되었습니다.'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('과목 수정 실패: $e')),
    );
  }
}



Future<bool> saveSubject(String subjectName) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인 정보가 없습니다.'),
        ),
      );
    }
    return false;
  }

  final semesterCode =
      '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

  final subjectsRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('semesters')
      .doc(semesterCode)
      .collection('subjects');

  try {
    // 현재 학기에 등록된 과목 확인
    final existingSubjects = await subjectsRef.get();

    final normalizedName = subjectName.trim().toLowerCase();

    // 동일한 이름의 과목이 있는지 검사
    final isDuplicate = existingSubjects.docs.any((doc) {
      final existingName =
          (doc.data()['name'] as String? ?? '')
              .trim()
              .toLowerCase();

      return existingName == normalizedName;
    });

    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$subjectName 과목은 이미 등록되어 있습니다.',
            ),
          ),
        );
      }
      return false;
    }

    // 중복이 없는 경우에만 저장
    await subjectsRef.add({
      'name': subjectName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return true;
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('과목 저장 실패: $e'),
        ),
      );
    }
    return false;
  }
}


Future<void> showAddSubjectDialog() async {
  final subjectName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      String inputName = '';

      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('수강 과목 추가'),
            content: TextField(
              autofocus: true,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '과목명',
                hintText: '예: 운영체제',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                inputName = value;
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (inputName.trim().isEmpty) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(
                      const SnackBar(
                        content: Text('과목명을 입력해주세요.'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    inputName.trim(),
                  );
                },
                child: const Text('추가'),
              ),
            ],
          );
        },
      );
    },
  );
  
    if (!mounted || subjectName == null) return;

    final success = await saveSubject(subjectName);

    if (!mounted) return;

    if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text('$subjectName 과목이 저장되었습니다!'),
            ),
        );
    }

}



  @override
  Widget build(BuildContext context) {
    final years = List.generate(
      11,
      (index) => DateTime.now().year - 5 + index,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      appBar: AppBar(
        title: const Text(
          '수강 과목 관리',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFF9F9FF),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '학기 선택',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF242B50),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '수강 과목을 관리할 학년도를 선택해주세요.',
              style: TextStyle(
                color: Color(0xFF66708F),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: selectedYear,
                    decoration: const InputDecoration(
                      labelText: '학년도',
                      border: OutlineInputBorder(),
                    ),
                    items: years.map((year) {
                      return DropdownMenuItem(
                        value: year,
                        child: Text('$year년'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedYear = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedSemester,
                    decoration: const InputDecoration(
                      labelText: '학기',
                      border: OutlineInputBorder(),
                    ),
                    items: ['1학기', '2학기'].map((semester) {
                      return DropdownMenuItem(
                        value: semester,
                        child: Text(semester),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(
                          () => selectedSemester = value,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            Text(
              '$selectedYear년 $selectedSemester 수강 과목',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF242B50),
              ),
            ),

            const SizedBox(height: 16),

           
            Expanded(
            child: Builder(
                builder: (context) {
                final user = FirebaseAuth.instance.currentUser;

                if (user == null) {
                    return const Center(
                    child: Text('로그인 정보가 없습니다.'),
                    );
                }

                final semesterCode =
                    '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('semesters')
                        .doc(semesterCode)
                        .collection('subjects')
                        .orderBy('createdAt')
                        .snapshots(),
                    builder: (context, snapshot) {
                    if (snapshot.hasError) {
                        return const Center(
                        child: Text('과목 목록을 불러오지 못했습니다.'),
                        );
                    }

                    if (!snapshot.hasData) {
                        return const Center(
                        child: CircularProgressIndicator(),
                        );
                    }

                    final subjects = snapshot.data!.docs;

                    if (subjects.isEmpty) {
                        return const Center(
                        child: Text(
                            '등록된 수강 과목이 없습니다.\n과목을 추가해보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF66708F),
                            ),
                        ),
                        );
                    }

                    return ListView.builder(
                        itemCount: subjects.length,
                        itemBuilder: (context, index) {
                        final subject = subjects[index];
                        final subjectName =
                            subject.data()['name'] as String? ?? '이름 없음';

                        return Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                            leading: const Icon(
                                Icons.menu_book_rounded,
                                color: Color(0xFF8576D8),
                            ),
                            title: Text(
                                subjectName,
                                style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                ),
                            ),
                            subtitle: const Text('수강 과목'),

                            
                            trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                IconButton(
                                icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Color(0xFF8576D8),
                                ),
                                tooltip: '과목 수정',
                                onPressed: () {
                                    editSubject(subject.id, subjectName);
                                },
                                ),
                                IconButton(
                                icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                ),
                                tooltip: '과목 삭제',
                                onPressed: () {
                                    deleteSubject(subject.id, subjectName);
                                },
                                ),
                            ],
                            ),


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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAddSubjectDialog,
        backgroundColor: const Color(0xFF8576D8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('과목 추가'),
      ),
    );
  }
}
