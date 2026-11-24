import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'screens/study_home_screen.dart';
import 'screens/study_note_screen.dart';
import 'services/ai_error.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/profile_setup_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const StudyAiApp());
}

class StudyAiApp extends StatelessWidget {
  const StudyAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Study AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9185E8)),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text('로그인 상태를 확인할 수 없습니다.')),
            );
          }

         if (snapshot.hasData) {
          final user = snapshot.data!;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            key: ValueKey(user.uid),
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (profileSnapshot.hasError) {
                return const Scaffold(
                  body: Center(
                    child: Text('학습 프로필을 불러오지 못했습니다.'),
                  ),
                );
              }

              final profile = profileSnapshot.data?.data();

              if (profile?['profileCompleted'] == true) {
                return StudyHomeScreen(
                  key: ValueKey(user.uid),
                  userId: user.uid,
                  profileName: profile?['name'] is String ? profile!['name'] as String : null,
                  profile: profile ?? const {},
                  uploadScreenBuilder: (context) => const PdfUploadPage(),
                );
              }
              return const ProfileSetupScreen();
            },
          );
        }

          return const LoginScreen();
        },
      ),
    );
  }
}

class PdfUploadPage extends StatefulWidget {
  const PdfUploadPage({super.key});

  @override
  State<PdfUploadPage> createState() => _PdfUploadPageState();
}

class _PdfUploadPageState extends State<PdfUploadPage> {
  String? selectedFileName;
  String extractedText = '';
  bool isPickingFile = false;
  String summaryText = '';
  bool isSummarizing = false;
  bool isTextExpanded = false;

    // 현재 선택한 학기와 과목 정보
  int selectedYear = DateTime.now().year;
  String selectedSemester =
      DateTime.now().month <= 6 ? '1학기' : '2학기';

  String? selectedSubjectId;
  String? selectedSubjectName;

  // Firestore 학기 문서 ID (예: 2026-2)
  String get selectedSemesterCode =>
      '$selectedYear-${selectedSemester == '1학기' ? '1' : '2'}';

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


  Future<void> pickPdfFile() async {
    if (isPickingFile) return;
    setState(() => isPickingFile = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted) return;
      if (result.isEmpty) return;
      final file = result.first;
      setState(() {
        selectedFileName = file.name;
        extractedText = '';
        summaryText = '';
        isTextExpanded = false;
      });
      if (file.path == null) {
        throw Exception('PDF 파일 경로를 찾을 수 없습니다.');
      }
      final bytes = await File(file.path!).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      String text;
      try {
        text = PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }
      if (!mounted) return;
      setState(() {
        extractedText = text.trim().isEmpty
            ? '추출된 텍스트가 없습니다. 이미지 PDF일 수 있습니다.'
            : text;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 처리 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => isPickingFile = false);
    }
  }

  Future<void> summarizePdf() async {
  if (extractedText.trim().isEmpty ||
      extractedText.startsWith('추출된 텍스트가 없습니다.')) {
    return;
  }

  setState(() {
    isSummarizing = true;
  });

    try {
      final url = Uri.parse('http://127.0.0.1:8000/summarize');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': extractedText.length > 30000
                  ? extractedText.substring(0, 30000)
                  : extractedText,
            }),
          )
          .timeout(const Duration(seconds: 240));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map<String, dynamic> || data['summary'] is! String ||
            (data['summary'] as String).trim().isEmpty) {
          throw const FormatException('Invalid summary response');
        }

        if (!mounted) return;

        final generatedSummary = data['summary'] as String;

        setState(() {
          summaryText = generatedSummary;
          isSummarizing = false;
        });

        // AI 요약 완료 후 학습 노트 화면으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StudyNoteScreen(
              fileName: selectedFileName ?? '강의자료',
              summaryText: generatedSummary,
              originalText: extractedText,
              subjectId: selectedSubjectId,
              semesterCode: selectedSemesterCode,
            ),
          ),
        );
      } else {
        throw AiHttpException(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aiErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => isSummarizing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('강의자료 업로드'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.picture_as_pdf, size: 80, color: Color(0xFF9185E8)),
            const SizedBox(height: 20),
            const Text('강의자료 PDF를 업로드하세요', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            // 학년도 및 학기 선택
            Row(
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
                      11,
                      (index) => DateTime.now().year - 5 + index,
                    ).map((year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text('$year년'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        selectedYear = value;
                        selectedSubjectId = null;
                        selectedSubjectName = null;
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
                    items: ['1학기', '2학기'].map((semester) {
                      return DropdownMenuItem<String>(
                        value: semester,
                        child: Text(semester),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setState(() {
                        selectedSemester = value;
                        selectedSubjectId = null;
                        selectedSubjectName = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 과목 선택
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: subjectsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    '과목 목록을 불러오지 못했습니다.',
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final subjects = snapshot.data!.docs;

                if (subjects.isEmpty) {
                  return const Text(
                    '현재 학기에 등록된 과목이 없습니다. '
                    '수강 과목 관리에서 먼저 과목을 등록해주세요.',
                  );
                }

                final currentSubjectId = subjects.any(
                  (subject) => subject.id == selectedSubjectId,
                )
                    ? selectedSubjectId
                    : null;

                return DropdownButtonFormField<String>(
                  key: ValueKey(
                    '$selectedSemesterCode-$currentSubjectId',
                  ),
                  initialValue: currentSubjectId,
                  decoration: const InputDecoration(
                    labelText: '수강 과목 선택',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                  hint: const Text('PDF를 저장할 과목을 선택하세요'),
                  items: subjects.map((subject) {
                    final subjectName =
                        subject.data()['name'] as String? ?? '이름 없음';

                    return DropdownMenuItem<String>(
                      value: subject.id,
                      child: Text(subjectName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    final selected = subjects.firstWhere(
                      (subject) => subject.id == value,
                    );

                    setState(() {
                      selectedSubjectId = value;
                      selectedSubjectName =
                          selected.data()['name'] as String?;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            
            ElevatedButton.icon(
              onPressed: isPickingFile || selectedSubjectId == null
                  ? null
                  : pickPdfFile,
              icon: const Icon(Icons.upload_file),
              label: Text(
                isPickingFile ? 'PDF 처리 중...' : 'PDF 파일 선택',
              ),
            ),

            const SizedBox(height: 24),
            if (selectedFileName != null) ...[
              Text('선택한 파일: $selectedFileName',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Text('추출된 PDF 텍스트',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column( 
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '추출된 텍스트',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    SelectableText(
                      isTextExpanded || extractedText.length <= 50
                          ? extractedText
                          : '${extractedText.substring(0, 50)}...',
                    ),

                    if (extractedText.length > 50)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              isTextExpanded = !isTextExpanded;
                            });
                          },
                          icon: Icon(
                            isTextExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          label: Text(
                            isTextExpanded ? '접기' : '더보기',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // AI 요약하기 버튼
              ElevatedButton.icon(
                onPressed: isSummarizing ||
                        extractedText.trim().length < 10 ||
                        extractedText.startsWith('추출된 텍스트가 없습니다.')
                    ? null
                    : summarizePdf,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  isSummarizing ? 'AI 요약 중...' : 'AI 요약하기',
                ),
              ),

              // 요약 중 로딩 표시
              if (isSummarizing) ...[
                const SizedBox(height: 20),
                const Center(
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gemini가 강의자료를 분석하고 있습니다...',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
