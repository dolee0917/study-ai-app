
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'quiz_screen.dart';
import '../services/study_storage.dart';

class StudyNoteScreen extends StatefulWidget {
  final String fileName;
  final String summaryText;
  final String originalText;
  final bool isFromHistory;
  // 선택한 과목 및 학기 정보
  final String? subjectId;
  final String? semesterCode;

  const StudyNoteScreen({
    super.key,
    required this.fileName,
    required this.summaryText,
    required this.originalText,
    this.isFromHistory = false,
    this.subjectId,
    this.semesterCode,
  });


  @override
  State<StudyNoteScreen> createState() => _StudyNoteScreenState();
}

class _StudyNoteScreenState extends State<StudyNoteScreen> {
  bool isGeneratingQuiz = false;
  List<dynamic> quizQuestions = [];
  bool isSaving = false;
  bool isSaved = false;
  late String? _noteId = widget.isFromHistory
      ? null
      : '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<String> _saveNote(List<dynamic> questions) async {
    final id = _noteId ?? await StudyStorage.findExistingNoteId(
      fileName: widget.fileName,
      summaryText: widget.summaryText,
      originalText: widget.originalText,
      subjectId: widget.subjectId,
      semesterCode: widget.semesterCode,
    );
    final savedId = await StudyStorage.saveNote(
      noteId: id,
      fileName: widget.fileName,
      summaryText: widget.summaryText,
      originalText: widget.originalText,
      questions: questions,
      subjectId: widget.subjectId,
      semesterCode: widget.semesterCode,
    );
    _noteId = savedId;
    return savedId;
  }

  
    Future<void> generateQuiz() async {
    if (isGeneratingQuiz || isSaving) return;

    setState(() {
        isGeneratingQuiz = true;
    });

    try {
        // 실제 Galaxy S24에서 연결되는 PC의 IPv4 주소 사용
        // 아래 주소는 예시이므로 반드시 변경하세요.
        final url = Uri.parse(
        'http://127.0.0.1:8000/generate-quiz',
        );

        final text = widget.originalText;

        final response = await http.post(
        url,
        headers: {
            'Content-Type': 'application/json',
        },
        body: jsonEncode({
            'text': text.length > 30000
                ? text.substring(0, 30000)
                : text,
        }),
        ).timeout(const Duration(seconds: 240));

        if (response.statusCode != 200) {
        throw Exception(
            '서버 오류 (${response.statusCode}): '
            '${utf8.decode(response.bodyBytes)}',
        );
        }

        final data = jsonDecode(
        utf8.decode(response.bodyBytes),
        );

        if (data is! Map<String, dynamic> ||
            data['questions'] is! List) {
        throw const FormatException('문제 데이터 형식이 올바르지 않습니다.');
        }

        final generatedQuestions = data['questions'] as List<dynamic>;

if (generatedQuestions.isEmpty) {
  throw const FormatException('생성된 복습 문제가 없습니다.');
}
if (generatedQuestions.any((item) =>
    item is! Map || item['type'] is! String ||
    item['question'] is! String || (item['question'] as String).trim().isEmpty ||
    item['answer'] is! String || (item['answer'] as String).trim().isEmpty ||
    (item['type'] == 'multiple_choice' &&
        (item['options'] is! List || (item['options'] as List).isEmpty)))) {
  throw const FormatException('문제 데이터 형식이 올바르지 않습니다.');
}

await _saveNote(generatedQuestions);
if (!mounted) return;
setState(() {
  quizQuestions = generatedQuestions;
  isSaved = true;
});

await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => QuizScreen(
      questions: generatedQuestions,
      fileName: widget.fileName,
      subjectId: widget.subjectId,
      semesterCode: widget.semesterCode,
    ),
  ),
);

    } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('복습 문제 생성 중 오류가 발생했습니다: $e'),
        ),
        );
    } finally {
        if (mounted) {
        setState(() {
            isGeneratingQuiz = false;
        });
        }
    }
    }

    
    Future<void> saveStudyNote() async {
      if (isSaving || isSaved || isGeneratingQuiz) return;

      setState(() {
        isSaving = true;
      });

      try {
        await _saveNote(quizQuestions);

        if (!mounted) return;

        setState(() {
          isSaved = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI 학습 노트가 저장되었습니다.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('학습 노트 저장 중 오류가 발생했습니다: $e'),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            isSaving = false;
          });
        }
      }
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 학습 노트'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 강의자료 정보
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF1EEFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.menu_book,
                    color: Color(0xFF9185E8),
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gemini AI가 생성한 강의자료 요약',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              '핵심 요약',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5143A8),
              ),
            ),

            const SizedBox(height: 16),

            // Markdown 요약 결과
            MarkdownBody(
              data: widget.summaryText,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 15,
                  height: 1.7,
                ),
                h1: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5143A8),
                ),
                h2: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5143A8),
                ),
                h3: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6759BC),
                ),
                strong: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF42358F),
                ),
                pPadding: const EdgeInsets.only(bottom: 8),
                h2Padding: const EdgeInsets.only(
                  top: 16,
                  bottom: 8,
                ),
              ),
            ),

            SizedBox(
              height: widget.isFromHistory ? 0 : 32,
            ),
            
            if (!widget.isFromHistory) ...[
              ElevatedButton.icon(
                onPressed: (isSaving || isSaved || isGeneratingQuiz) ? null : saveStudyNote,
                icon: Icon(
                  isSaved ? Icons.check_circle : Icons.save_outlined,
                ),
                label: Text(
                  isSaving
                      ? '학습 노트 저장 중...'
                      : isSaved
                          ? '학습 노트 저장 완료'
                          : 'AI 학습 노트 저장하기',
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 16),


            // 향후 복습 문제 기능 연결 예정
            ElevatedButton.icon(
                onPressed: (isGeneratingQuiz || isSaving) ? null : generateQuiz,
                icon: const Icon(Icons.quiz_outlined),
                label: Text(
                    isGeneratingQuiz
                        ? '복습 문제 생성 중...'
                        : '복습 문제 생성하기',
                ),
                ),

                if (isGeneratingQuiz) ...[
                const SizedBox(height: 20),
                const Center(
                    child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 12),
                const Text(
                    '복습 문제를 생성하고 있습니다...',
                    textAlign: TextAlign.center,
                ),
                ],
          ],
        ),
      ),
      ),
    );
  }
}
