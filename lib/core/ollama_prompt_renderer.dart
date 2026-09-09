import '../models/chat_message.dart';

/// Reproduces the exact Ollama gemma3:1b message template.
///
/// Ollama maps both `system` and `user` roles to Gemma's user turn.
class OllamaGemma3PromptRenderer {
  const OllamaGemma3PromptRenderer();

  String render(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'Must not be empty');
    }

    final out = StringBuffer();
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final isLast = i == messages.length - 1;

      switch (message.role) {
        case ChatRole.user:
        case ChatRole.system:
          out
            ..writeln('<start_of_turn>user')
            ..write(message.content)
            ..writeln('<end_of_turn>');
          if (isLast) {
            out.writeln('<start_of_turn>model');
          }
        case ChatRole.assistant:
          out
            ..writeln('<start_of_turn>model')
            ..write(message.content);
          if (!isLast) {
            out.writeln('<end_of_turn>');
          }
      }
    }
    return out.toString();
  }
}
