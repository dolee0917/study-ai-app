import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai_app/screens/exam_date_utils.dart';
import 'package:study_ai_app/screens/study_home_screen.dart';

HomeExam exam(String id, DateTime? date, {String? subject = 'math'}) => HomeExam(
  id: id, title: '시험 $id', date: date, semesterCode: '2026-1', subjectId: subject,
);

void main() {
  test('오늘 이후 가장 가까운 날짜와 같은 날짜의 문서 ID 순서', () {
    final now = DateTime(2026, 5, 10, 20);
    final selected = nearestHomeExam([
      exam('past', DateTime(2026, 5, 9, 23)),
      exam('later', DateTime(2026, 5, 12)),
      exam('b', DateTime(2026, 5, 10, 1)),
      exam('a', DateTime(2026, 5, 10, 23)),
      exam('invalid', null),
    ], now);
    expect(selected?.id, 'a');
    expect(nearestHomeExam([exam('past', DateTime(2026, 5, 9))], now), isNull);
    expect(daysUntilExam(DateTime(2026, 5, 11), now: now), 1);
    expect(examDDayText(daysUntilExam(DateTime(2026, 5, 10), now: now)), 'D-Day');
  });

  testWidgets('일정 스트림과 복귀 갱신에 따라 현황이 갱신된다', (tester) async {
    final stream = StreamController<List<HomeExam>>.broadcast();
    addTearDown(stream.close);
    final key = GlobalKey<ExamStatusCardState>();
    var remaining = 2;
    var calls = 0;
    final today = DateTime.now();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamStatusCard(
      key: key, uid: 'user', exams: stream.stream,
      subjectLoader: (_, _) async => '수학',
      statsLoader: (_, _) async { calls++; return {
        'remainingWeakCount': remaining, 'resolutionRate': 50.0,
      }; },
      countLoader: (_, _) async => 6,
    ))));
    stream.add([]);
    await tester.pump();
    expect(find.text('예정된 시험이 없습니다.'), findsOneWidget);
    stream.add([exam('one', today)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('시험 one'), findsOneWidget);
    expect(find.text('과목: 수학'), findsOneWidget);
    expect(find.textContaining('남은 취약 문제: 2개'), findsOneWidget);
    expect(find.textContaining('취약 문제 해소율: 50.0%'), findsOneWidget);
    expect(find.text('오늘의 추천 복습: 6문제'), findsOneWidget);
    expect(find.textContaining('D-Day'), findsOneWidget);
    stream.add([exam('one', today)]);
    await tester.pump();
    expect(calls, 1);
    remaining = 1;
    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('남은 취약 문제: 1개'), findsOneWidget);
    stream.add([exam('two', today)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('시험 two'), findsOneWidget);
    expect(find.text('시험 one'), findsNothing);
    stream.add([]);
    await tester.pump();
    expect(find.text('예정된 시험이 없습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('과목과 통계 실패 시 제목과 D-day를 유지한다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamStatusCard(
      uid: 'user', exams: Stream.value([exam('one', DateTime.now())]),
      subjectLoader: (_, _) async => throw StateError('subject'),
      statsLoader: (_, _) async => throw StateError('stats'),
      countLoader: (_, _) async => throw StateError('count'),
    ))));
    await tester.pump();
    await tester.pump();
    expect(find.text('시험 one'), findsOneWidget);
    expect(find.textContaining('D-Day'), findsOneWidget);
    expect(find.text('과목: 과목 조회 실패'), findsOneWidget);
    expect(find.text('취약 문제 통계를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('추천 문제를 불러오지 못했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('시험 조회 실패 안내', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamStatusCard(
      uid: 'user', exams: Stream<List<HomeExam>>.error(StateError('firestore')),
    ))));
    await tester.pump();
    expect(find.text('시험 일정을 불러오지 못했습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('선택 시험이 바뀌면 이전 비동기 결과를 표시하지 않는다', (tester) async {
    final stream = StreamController<List<HomeExam>>.broadcast();
    addTearDown(stream.close);
    final oldSubject = Completer<String>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExamStatusCard(
      uid: 'user', exams: stream.stream,
      subjectLoader: (_, subject) => subject == 'old'
          ? oldSubject.future : Future.value('새 과목'),
      statsLoader: (_, _) async => {'remainingWeakCount': 0, 'resolutionRate': 0.0},
      countLoader: (_, _) async => 0,
    ))));
    stream.add([exam('old', DateTime.now(), subject: 'old')]);
    await tester.pump();
    stream.add([exam('new', DateTime.now(), subject: 'new')]);
    await tester.pump();
    await tester.pump();
    oldSubject.complete('이전 과목');
    await tester.pump();
    expect(find.text('과목: 새 과목'), findsOneWidget);
    expect(find.text('과목: 이전 과목'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('계정 변경 시 이전 계정의 시험을 표시하지 않는다', (tester) async {
    final first = StreamController<List<HomeExam>>.broadcast();
    final second = StreamController<List<HomeExam>>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);
    Widget card(String uid, Stream<List<HomeExam>> exams) => MaterialApp(
      home: Scaffold(body: ExamStatusCard(
        uid: uid, exams: exams,
        subjectLoader: (_, _) async => '과목',
        statsLoader: (_, _) async => {'remainingWeakCount': 0, 'resolutionRate': 0.0},
        countLoader: (_, _) async => 0,
      )),
    );
    await tester.pumpWidget(card('first', first.stream));
    first.add([exam('first', DateTime.now())]);
    await tester.pump();
    expect(find.text('시험 first'), findsOneWidget);
    await tester.pumpWidget(card('second', second.stream));
    expect(find.text('시험 first'), findsNothing);
    second.add([exam('second', DateTime.now())]);
    await tester.pump();
    expect(find.text('시험 second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
