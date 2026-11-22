import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai_app/screens/exam_management_screen.dart';

void main() {
  testWidgets('삭제 버튼과 확인 대화상자, 취소 시 데이터 유지', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamDeleteButton(
      title: '수학 시험', delete: () async { calls++; },
    ))));
    expect(find.byTooltip('시험 일정 삭제'), findsOneWidget);
    await tester.tap(find.byTooltip('시험 일정 삭제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('수학 시험'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byTooltip('시험 일정 삭제'), findsOneWidget);
  });

  testWidgets('확정한 시험만 삭제하고 목록에서 갱신한다', (tester) async {
    final exams = {'exam-1': '수학 시험', 'exam-2': '영어 시험'};
    final relatedData = ['subject', 'pdf', 'study records'];
    final deleted = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, update) => Column(children: [
        for (final entry in exams.entries)
          Row(key: ValueKey(entry.key), children: [
            Text(entry.value),
            ExamDeleteButton(
              key: ValueKey('delete-${entry.key}'), title: entry.value,
              delete: () async {
                deleted.add(entry.key);
                update(() => exams.remove(entry.key));
              },
            ),
          ]),
      ]),
    ))));
    await tester.tap(find.byKey(const ValueKey('delete-exam-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(deleted, ['exam-1']);
    expect(find.text('수학 시험'), findsNothing);
    expect(find.text('영어 시험'), findsOneWidget);
    expect(relatedData, ['subject', 'pdf', 'study records']);
    expect(find.text('시험 일정이 삭제되었습니다.'), findsOneWidget);
  });

  testWidgets('삭제 실패는 오류를 표시하고 일정을 유지한다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const Text('수학 시험'),
      ExamDeleteButton(title: '수학 시험', delete: () async => throw StateError('failed')),
    ]))));
    await tester.tap(find.byTooltip('시험 일정 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('시험 일정을 삭제하지 못했습니다.'), findsOneWidget);
    expect(find.text('수학 시험'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
  });

  testWidgets('삭제가 진행되는 동안 중복 요청을 막는다', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamDeleteButton(
      title: '수학 시험', delete: () { calls++; return pending.future; },
    ))));
    await tester.tap(find.byTooltip('시험 일정 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);
  });
}
