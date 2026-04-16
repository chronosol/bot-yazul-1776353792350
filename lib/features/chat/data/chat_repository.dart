import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/message.dart';
import '../../../core/constants/app_config.dart';

class ChatRepository {
  final Dio _dio;

  ChatRepository() : _dio = Dio(BaseOptions(
    baseUrl:        AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type':  'application/json',
      'X-Org-ID':      AppConfig.organisationId,
    },
  )) {
    _dio.interceptors.add(LogInterceptor(responseBody: false));
  }

  /// Send a message and return the bot's reply.
  Future<ChatMessage> sendMessage({
    required String sessionId,
    required String userMessage,
    required List<ChatMessage> history,
  }) async {
    try {
      final response = await _dio.post(
        AppConfig.chatEndpoint,
        data: {
          'session_id':      sessionId,
          'organisation_id': AppConfig.organisationId,
          'message':         userMessage,
          'history': history
              .where((m) => m.type == MessageType.text)
              .take(20)
              .map((m) => {
                    'role':    m.isBot ? 'assistant' : 'user',
                    'content': m.content,
                  })
              .toList(),
        },
      );

      final data    = response.data as Map<String, dynamic>;
      final content = data['reply'] as String? ?? data['message'] as String? ?? 'Sorry, I could not process that.';

      return ChatMessage.bot(content);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) throw ChatException('Too many requests — please wait a moment.');
      if (status != null && status >= 500) throw ChatException('Server error — please try again.');
      if (e.type == DioExceptionType.connectionTimeout) throw ChatException('Connection timed out — check your internet.');
      throw ChatException('Could not reach the assistant: ${e.message}');
    } catch (e) {
      throw ChatException('Unexpected error: $e');
    }
  }
}

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);
  @override
  String toString() => message;
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository());
