
import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import 'study_note_screen.dart';

class StudyHistoryScreen extends StatefulWidget {
  const StudyHistoryScreen({super.key});

  @override
  State<StudyHistoryScreen> createState() =>
      _StudyHistoryScreenState();
}

class _StudyHistoryScreenState
    extends State<StudyHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _refreshNotes();
  }

  void _refreshNotes() {
    _notesFuture = StudyStorage.loadNotes();
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
        ),
      ),
    );

    if (!mounted) return;

    setState(_refreshNotes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학습 기록'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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

          final notes = snapshot.data ?? [];

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
    );
  }
}
