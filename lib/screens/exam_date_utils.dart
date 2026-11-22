int? daysUntilExam(DateTime? examDate, {DateTime? now}) {
  if (examDate == null) return null;
  final today = now ?? DateTime.now();
  final todayDate = DateTime.utc(today.year, today.month, today.day);
  final examDay = DateTime.utc(examDate.year, examDate.month, examDate.day);
  return examDay.difference(todayDate).inDays;
}

String? examDDayText(int? days) {
  if (days == null) return null;
  if (days < 0) return '시험 종료';
  if (days == 0) return 'D-Day';
  return 'D-$days';
}
