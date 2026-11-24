import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_ai_app/services/ai_error.dart';
import 'package:study_ai_app/services/study_storage.dart';
import 'package:study_ai_app/screens/study_note_screen.dart';

void main() {
  test('오류 식별자별 사용자 안내를 표시한다', () {
    final cases = {
      'AI_UNAVAILABLE': 'AI 서버에 요청이 집중되고 있습니다. 잠시 후 다시 시도해주세요.',
      'AI_RATE_LIMIT': 'AI 서비스 사용량 제한에 도달했습니다. 잠시 후 다시 시도해주세요.',
      'AI_MODEL_NOT_FOUND': 'AI 서비스 설정에 문제가 발생했습니다.',
      'AI_AUTH_ERROR': 'AI 서비스 연결 설정에 문제가 발생했습니다.',
      'AI_EMPTY_RESPONSE': 'AI가 결과를 생성하지 못했습니다. 다시 시도해주세요.',
      'AI_INVALID_RESPONSE': 'AI가 생성한 결과의 형식이 올바르지 않습니다. 다시 시도해주세요.',
      'AI_CONFIG_ERROR': 'AI 서비스 설정에 문제가 발생했습니다.',
      'AI_UNKNOWN_ERROR': 'AI 결과 생성 중 오류가 발생했습니다. 다시 시도해주세요.',
    };
    for (final entry in cases.entries) {
      expect(aiErrorMessage(AiHttpException(502, '{"code":"${entry.key}"}')), entry.value);
    }
  });

  test('기존 응답과 라우트 404를 안전하게 처리하고 내부 내용을 표시하지 않는다', () {
    expect(aiErrorMessage(const AiHttpException(404, '{"detail":"Not Found"}')),
      '서버 요청 경로를 찾을 수 없습니다.');
    expect(aiErrorMessage(const AiHttpException(502, '{"detail":"PRIVATE_SECRET"}')),
      'AI 결과 생성 중 오류가 발생했습니다. 다시 시도해주세요.');
    expect(aiErrorMessage(const AiHttpException(429, 'not json')),
      'AI 서비스 사용량 제한에 도달했습니다. 잠시 후 다시 시도해주세요.');
    expect(aiErrorMessage(const AiHttpException(503, '{}')),
      'AI 서버에 요청이 집중되고 있습니다. 잠시 후 다시 시도해주세요.');
  });

  test('연결 실패와 시간 초과를 구분한다', () {
    expect(aiErrorMessage(const SocketException('secret')),
      '서버에 연결할 수 없습니다. 연결 상태를 확인해주세요.');
    expect(aiErrorMessage(TimeoutException('secret')),
      '응답 시간이 초과되었습니다. 다시 시도해주세요.');
  });

  testWidgets('문제 생성 오류 후 로딩이 해제되고 기존 노트가 유지된다', (tester) async {
    final originalUser = StudyStorage.currentUserId;
    StudyStorage.currentUserId = () => 'alice';
    addTearDown(() => StudyStorage.currentUserId = originalUser);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StudyNoteScreen(
        fileName: '자료.pdf', summaryText: '기존 요약', originalText: '기존 학습 자료 내용입니다',
      )));
      await tester.ensureVisible(find.text('복습 문제 생성하기'));
      await tester.tap(find.text('복습 문제 생성하기'));
      await tester.pumpAndSettle();
      expect(find.text('AI 서비스 사용량 제한에 도달했습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('복습 문제 생성하기'), findsOneWidget);
      expect(find.text('복습 문제 생성 중...'), findsNothing);
      expect(find.text('기존 요약'), findsOneWidget);
    }, () => MockClient((_) async => http.Response('{"code":"AI_RATE_LIMIT"}', 429)));
  });
}
