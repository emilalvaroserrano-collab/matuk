import 'package:flutter/material.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';
import '../widgets/language_panel.dart';
import '../widgets/setup_card.dart';

class DualTranslatorScreen extends StatelessWidget {
  const DualTranslatorScreen({
    super.key,
    required this.controller,
  });

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Translator Mode'),
            actions: [
              if (controller.ready)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.55),
                      ),
                      child: const Text('LOCAL'),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: controller.ready
                  ? _TranslatorBody(controller: controller)
                  : SetupCard(
                      status: controller.setupStatus,
                      progress: controller.setupProgress,
                      preparing: controller.preparing,
                      error: controller.error,
                      onPrepare: controller.prepareOfflineModels,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _TranslatorBody extends StatelessWidget {
  const _TranslatorBody({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final busy = controller.generating || controller.listeningSide != null;
    return Column(
      children: [
        LanguagePanel(
          language: controller.languageA,
          text: controller.textA,
          listening: controller.listeningSide == TranslationSide.a,
          busy: busy,
          onLanguageChanged: (language) =>
              controller.setLanguage(TranslationSide.a, language),
          onMic: () => controller.toggleListening(TranslationSide.a),
          onSpeak: () => controller.replay(TranslationSide.a),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Swap languages',
                onPressed: busy ? null : controller.swapLanguages,
                icon: const Icon(Icons.swap_vert_rounded),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Auto speak'),
                  Switch(
                    value: controller.autoSpeak,
                    onChanged: controller.setAutoSpeak,
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Clear',
                onPressed: busy ? null : controller.clearConversation,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        LanguagePanel(
          language: controller.languageB,
          text: controller.textB,
          listening: controller.listeningSide == TranslationSide.b,
          busy: busy,
          onLanguageChanged: (language) =>
              controller.setLanguage(TranslationSide.b, language),
          onMic: () => controller.toggleListening(TranslationSide.b),
          onSpeak: () => controller.replay(TranslationSide.b),
        ),
        if (controller.generating) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: controller.history.isEmpty
              ? Center(
                  child: Text(
                    'Conversation history will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.separated(
                  itemCount: controller.history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final turn = controller.history[index];
                    return _HistoryCard(turn: turn);
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.turn});

  final TranslationTurn turn;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0E0E12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Text(turn.sourceText),
            const SizedBox(height: 6),
            Text(
              turn.translatedText,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
