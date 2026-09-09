import 'package:flutter/material.dart';

import '../models/translation_language.dart';

class LanguagePanel extends StatelessWidget {
  const LanguagePanel({
    super.key,
    required this.language,
    required this.text,
    required this.listening,
    required this.busy,
    required this.onLanguageChanged,
    required this.onMic,
    required this.onSpeak,
  });

  final TranslationLanguage language;
  final String text;
  final bool listening;
  final bool busy;
  final ValueChanged<TranslationLanguage> onLanguageChanged;
  final VoidCallback onMic;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: const Color(0xFF111116),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TranslationLanguage>(
                      value: language,
                      isExpanded: true,
                      items: translationLanguages
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) onLanguageChanged(value);
                            },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Read aloud',
                  onPressed: text.trim().isEmpty ? null : onSpeak,
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            const Divider(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: SelectableText(
                text.isEmpty
                    ? (listening ? 'Listening…' : 'Tap the microphone and speak')
                    : text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      height: 1.45,
                      color: text.isEmpty
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: FilledButton.tonalIcon(
                onPressed: busy && !listening ? null : onMic,
                icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(listening ? 'Stop & translate' : 'Speak'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
