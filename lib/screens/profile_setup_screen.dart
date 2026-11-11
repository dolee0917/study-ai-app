import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameController = TextEditingController();
  final schoolController = TextEditingController();
  final majorController = TextEditingController();

  String selectedGrade = '1학년';
  String selectedSemester = '1학기';
  String selectedPurpose = '시험 대비';
  
  bool isSaving = false;

Future<void> saveProfile() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인 정보가 없습니다. 다시 로그인해주세요.')),
    );
    return;
  }

  final name = nameController.text.trim();
  final school = schoolController.text.trim();
  final major = majorController.text.trim();

  if (name.isEmpty || school.isEmpty || major.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이름, 학교, 전공을 모두 입력해주세요.')),
    );
    return;
  }

  setState(() => isSaving = true);

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
          'name': name,
          'school': school,
          'major': major,
          'grade': selectedGrade,
          'semester': selectedSemester,
          'purpose': selectedPurpose,
          'profileCompleted': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('학습 프로필이 저장되었습니다!')),
    );

    // 다음 단계에서 홈 화면으로 이동하는 기능 연결
  } on FirebaseException catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('저장 실패: ${e.code}')),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('오류가 발생했습니다: $e')),
    );
  } finally {
    if (mounted) {
      setState(() => isSaving = false);
    }
  }
}
  @override
  void dispose() {
    nameController.dispose();
    schoolController.dispose();
    majorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('학습 프로필 설정'),
        backgroundColor: const Color(0xFFF8F7FF),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.school_rounded,
                  size: 64,
                  color: Color(0xFF9185E8),
                ),

                const SizedBox(height: 16),

                const Text(
                  '학습 정보를 등록해주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  '나에게 맞는 학습 환경을 설정할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 32),

                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '이름 또는 닉네임',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: schoolController,
                  decoration: const InputDecoration(
                    labelText: '학교',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: majorController,
                  decoration: const InputDecoration(
                    labelText: '전공(학과)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedGrade,
                  decoration: const InputDecoration(
                    labelText: '학년',
                    border: OutlineInputBorder(),
                  ),
                  items: ['1학년', '2학년', '3학년', '4학년', '5학년 이상']
                      .map(
                        (grade) => DropdownMenuItem(
                          value: grade,
                          child: Text(grade),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedGrade = value);
                    }
                  },
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedSemester,
                  decoration: const InputDecoration(
                    labelText: '학기',
                    border: OutlineInputBorder(),
                  ),
                  items: ['1학기', '2학기']
                      .map(
                        (semester) => DropdownMenuItem(
                          value: semester,
                          child: Text(semester),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedSemester = value);
                    }
                  },
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedPurpose,
                  decoration: const InputDecoration(
                    labelText: '학습 목적',
                    border: OutlineInputBorder(),
                  ),
                  items: ['시험 대비']
                      .map(
                        (purpose) => DropdownMenuItem(
                          value: purpose,
                          child: Text(purpose),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedPurpose = value);
                    }
                  },
                ),

                const SizedBox(height: 28),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9185E8),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      '학습 시작하기',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}