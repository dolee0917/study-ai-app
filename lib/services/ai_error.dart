import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AiHttpException implements Exception {
  const AiHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

const _messages = <String, String>{
  'AI_UNAVAILABLE': 'AI 서버에 요청이 집중되고 있습니다. 잠시 후 다시 시도해주세요.',
  'AI_RATE_LIMIT': 'AI 서비스 사용량 제한에 도달했습니다. 잠시 후 다시 시도해주세요.',
  'AI_MODEL_NOT_FOUND': 'AI 서비스 설정에 문제가 발생했습니다.',
  'AI_AUTH_ERROR': 'AI 서비스 연결 설정에 문제가 발생했습니다.',
  'AI_EMPTY_RESPONSE': 'AI가 결과를 생성하지 못했습니다. 다시 시도해주세요.',
  'AI_INVALID_RESPONSE': 'AI가 생성한 결과의 형식이 올바르지 않습니다. 다시 시도해주세요.',
  'AI_CONFIG_ERROR': 'AI 서비스 설정에 문제가 발생했습니다.',
  'AI_UNKNOWN_ERROR': 'AI 결과 생성 중 오류가 발생했습니다. 다시 시도해주세요.',
};

String aiErrorMessage(Object error) {
  if (error is TimeoutException) return '응답 시간이 초과되었습니다. 다시 시도해주세요.';
  if (error is SocketException || error is http.ClientException) {
    return '서버에 연결할 수 없습니다. 연결 상태를 확인해주세요.';
  }
  if (error is FormatException || error is TypeError) return _messages['AI_INVALID_RESPONSE']!;
  if (error is AiHttpException) {
    try {
      final data = jsonDecode(error.body);
      if (data is Map && data['code'] is String && _messages.containsKey(data['code'])) {
        return _messages[data['code']]!;
      }
    } on FormatException {
      // Unstructured or legacy response: never display its contents.
    }
    if (error.statusCode == 404) return '서버 요청 경로를 찾을 수 없습니다.';
    if (error.statusCode == 429) return _messages['AI_RATE_LIMIT']!;
    if (error.statusCode == 503) return _messages['AI_UNAVAILABLE']!;
  }
  return _messages['AI_UNKNOWN_ERROR']!;
}
