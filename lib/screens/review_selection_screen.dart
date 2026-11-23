import 'package:flutter/material.dart';

import 'exam_management_screen.dart';
import 'wrong_answer_screen.dart';

class ReviewSelectionScreen extends StatelessWidget {
  const ReviewSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(title: const Text('복습하기'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _reviewCard(
              context,
              title: '맞춤 복습',
              subtitle: '시험 일정에 맞춰 복습해요',
              icon: Icons.tune_rounded,
              color: const Color(0xFFEDEAFF),
              destination: const ExamManagementScreen(),
            ),
            const SizedBox(height: 16),
            _reviewCard(
              context,
              title: '취약 문제 집중 복습',
              subtitle: '틀린 문제를 다시 풀어봐요',
              icon: Icons.refresh_rounded,
              color: const Color(0xFFE6F1FF),
              destination: const WrongAnswerScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget destination,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context, MaterialPageRoute<void>(builder: (_) => destination)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF8576D8), size: 30),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17,
                    fontWeight: FontWeight.bold, color: Color(0xFF242B50))),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF69718D))),
                ],
              )),
              const Icon(Icons.chevron_right, color: Color(0xFF8576D8)),
            ],
          ),
        ),
      ),
    );
  }
}
