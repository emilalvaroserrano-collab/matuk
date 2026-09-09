import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_voice_assistant/core/ollama_prompt_renderer.dart';
import 'package:gemma_voice_assistant/models/chat_message.dart';

void main() {
  const renderer = OllamaGemma3PromptRenderer();

  test('matches Ollama Gemma 3 single-turn framing', () {
    final actual = renderer.render(const [
      ChatMessage(role: ChatRole.user, content: 'Hello!'),
    ]);
    expect(
      actual,
      '<start_of_turn>user\nHello!<end_of_turn>\n<start_of_turn>model\n',
    );
  });

  test('matches Ollama Gemma 3 multi-turn framing', () {
    final actual = renderer.render(const [
      ChatMessage(role: ChatRole.user, content: 'Hi'),
      ChatMessage(role: ChatRole.assistant, content: 'Hello'),
      ChatMessage(role: ChatRole.user, content: 'Help me'),
    ]);
    expect(
      actual,
      '<start_of_turn>user\nHi<end_of_turn>\n'
      '<start_of_turn>model\nHello<end_of_turn>\n'
      '<start_of_turn>user\nHelp me<end_of_turn>\n'
      '<start_of_turn>model\n',
    );
  });

  test('maps system role to user as Ollama template does', () {
    final actual = renderer.render(const [
      ChatMessage(role: ChatRole.system, content: 'Be concise.'),
      ChatMessage(role: ChatRole.user, content: 'Explain this.'),
    ]);
    expect(actual, startsWith('<start_of_turn>user\nBe concise.<end_of_turn>\n'));
  });
}
