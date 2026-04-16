import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/message.dart';
import '../../data/chat_repository.dart';
import '../../../../core/constants/app_config.dart';
import '../widgets/chat_input_bar.dart';

class ChatController extends AsyncNotifier<ChatSession> {
  late final ChatRepository _repo;
  late final String _sessionId;

  @override
  Future<ChatSession> build() async {
    _repo      = ref.read(chatRepositoryProvider);
    _sessionId = const Uuid().v4();

    final session = ChatSession(
      id:        _sessionId,
      messages:  [ChatMessage.bot(AppConfig.welcomeMessage)],
      startedAt: DateTime.now(),
    );

    return session;
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final current = state.valueOrNull;
    if (current == null) return;

    // Optimistically add user message + typing indicator
    final userMsg = ChatMessage.user(trimmed);
    final typing = ChatMessage.typing();

    state = AsyncData(current.copyWith(
      messages: [...current.messages, userMsg, typing],
      isLoading: true,
    ));

    try {
      final reply = await _repo.sendMessage(
        sessionId: _sessionId,
        userMessage: trimmed,
        history: current.messages,
      );

      final updated = state.valueOrNull;
      if (updated == null) return;

      // Remove typing indicator, add reply, mark user message as read
      final newMessages = updated.messages
          .where((m) => m.type != MessageType.typing)
          .map((m) => m.id == userMsg.id ? m.copyWith(status: MessageStatus.read) : m)
          .toList()
        ..add(reply);

      state = AsyncData(updated.copyWith(messages: newMessages, isLoading: false));
    } catch (e) {
      final updated = state.valueOrNull;
      if (updated == null) return;

      final withoutTyping = updated.messages
          .where((m) => m.type != MessageType.typing)
          .map((m) => m.id == userMsg.id ? m.copyWith(status: MessageStatus.failed) : m)
          .toList();

      state = AsyncData(updated.copyWith(
        messages: withoutTyping,
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> sendAttachment(ChatAttachment attachment) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final msgType = attachment.type == AttachmentType.image
        ? MessageType.image
        : attachment.type == AttachmentType.audio
            ? MessageType.audio
            : MessageType.file;

    final userMsg = ChatMessage.userWithAttachment(
      content: '',
      file: attachment.file,
      name: attachment.name,
      mimeType: attachment.mimeType,
      msgType: msgType,
    );

    state = AsyncData(current.copyWith(
      messages: [...current.messages, userMsg],
      isLoading: true,
    ));

    try {
      final reply = await _repo.sendMessage(
        sessionId: _sessionId,
        userMessage: '[Attachment: ${attachment.name}]',
        history: current.messages,
      );

      final updated = state.valueOrNull;
      if (updated == null) return;

      final newMessages = updated.messages
          .map((m) => m.id == userMsg.id ? m.copyWith(status: MessageStatus.read) : m)
          .toList()
        ..add(reply);

      state = AsyncData(updated.copyWith(messages: newMessages, isLoading: false));
    } catch (e) {
      final updated = state.valueOrNull;
      if (updated == null) return;

      final newMessages = updated.messages
          .map((m) => m.id == userMsg.id ? m.copyWith(status: MessageStatus.failed) : m)
          .toList();

      state = AsyncData(updated.copyWith(
        messages: newMessages,
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  void clearError() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(errorMessage: null));
  }

  void retryLastMessage() {
    final current = state.valueOrNull;
    if (current == null) return;

    final failed = current.messages.lastWhere(
      (m) => m.isUser && m.status == MessageStatus.failed,
      orElse: () => current.messages.last,
    );

    if (failed.isUser && failed.status == MessageStatus.failed) {
      final withoutFailed = current.messages.where((m) => m.id != failed.id).toList();
      state = AsyncData(current.copyWith(messages: withoutFailed));
      sendMessage(failed.content);
    }
  }
}

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, ChatSession>(ChatController.new);
