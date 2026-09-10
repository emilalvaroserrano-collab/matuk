import 'package:flutter/material.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';

class ReferenceStyleTranslatorScreen extends StatefulWidget {
  const ReferenceStyleTranslatorScreen({super.key, required this.controller});

  final TranslatorController controller;

  @override
  State<ReferenceStyleTranslatorScreen> createState() =>
      _ReferenceStyleTranslatorScreenState();
}

class _ReferenceStyleTranslatorScreenState
    extends State<ReferenceStyleTranslatorScreen> {
  TranslatorController get controller => widget.controller;
  TranslationSide _activeSide = TranslationSide.a;

  Future<void> _toggleMic() async {
    if (!controller.ready) {
      await controller.prepareOfflineModels();
      return;
    }
    await controller.toggleMicMute(hint: _activeSide);
  }

  Future<void> _toggleSession() async {
    if (!controller.ready) {
      await controller.prepareOfflineModels();
      return;
    }
    await controller.toggleVoiceSession(hint: _activeSide);
  }

  Future<void> _replay() async {
    final side = controller.lastOutputSide;
    if (side != null) await controller.replay(side);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final latest = controller.history.isEmpty ? null : controller.history.first;
        final isListening = controller.listeningSide != null;

        String inputText = '';
        String translationText = '';
        bool inputIsFinal = false;

        if (isListening && controller.liveTranscript.trim().isNotEmpty) {
          inputText = controller.liveTranscript.trim();
        } else if (controller.generating) {
          final side = controller.speakerHint;
          inputText = side == TranslationSide.a
              ? controller.textA.trim()
              : controller.textB.trim();
          translationText = side == TranslationSide.a
              ? controller.textB.trim()
              : controller.textA.trim();
          inputIsFinal = inputText.isNotEmpty;
        } else if (latest != null) {
          inputText = latest.sourceText.trim();
          translationText = latest.translatedText.trim();
          inputIsFinal = true;
        } else {
          final a = controller.textA.trim();
          final b = controller.textB.trim();
          inputText = a.isNotEmpty ? a : b;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF101214),
          body: SafeArea(
            child: Column(
              children: [
                _Header(controller: controller),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LanguageRow(
                              controller: controller,
                              activeSide: _activeSide,
                              onSideChanged: (side) {
                                if (controller.voiceSessionActive || controller.busy) {
                                  return;
                                }
                                setState(() => _activeSide = side);
                              },
                            ),
                            const SizedBox(height: 28),
                            if (!controller.ready || controller.preparing)
                              _ModelSetup(controller: controller)
                            else if (inputText.isEmpty && translationText.isEmpty)
                              _EmptyState(controller: controller)
                            else ...[
                              _TurnBlock(
                                label: 'Input',
                                text: inputText,
                                finalTurn: inputIsFinal,
                                accent: const Color(0xFF5FA8FF),
                                placeholder: 'Listening…',
                              ),
                              const SizedBox(height: 16),
                              _TurnBlock(
                                label: 'Translation',
                                text: translationText,
                                finalTurn: !controller.generating &&
                                    translationText.isNotEmpty,
                                accent: const Color(0xFF69D391),
                                placeholder: controller.generating
                                    ? 'Translating locally…'
                                    : 'Waiting for translation…',
                                emphasized: true,
                              ),
                            ],
                            if (controller.error != null) ...[
                              const SizedBox(height: 18),
                              Text(
                                controller.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _BottomBar(
                  controller: controller,
                  onMic: _toggleMic,
                  onSpeaker: _replay,
                  onReset: controller.clearConversation,
                  onPlay: _toggleSession,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dual Translate',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  '100% local realtime translator',
                  style: TextStyle(fontSize: 13, color: Colors.white54),
                ),
              ],
            ),
          ),
          Text(
            controller.setupStatus,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.controller,
    required this.activeSide,
    required this.onSideChanged,
  });

  final TranslatorController controller;
  final TranslationSide activeSide;
  final ValueChanged<TranslationSide> onSideChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(TranslationSide side, TranslationLanguage language) {
      final selected = activeSide == side;
      return ChoiceChip(
        selected: selected,
        onSelected: (_) => onSideChanged(side),
        label: Text(language.displayName),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        chip(TranslationSide.a, controller.languageA),
        const Icon(Icons.swap_horiz_rounded, color: Colors.white38),
        chip(TranslationSide.b, controller.languageB),
      ],
    );
  }
}

class _TurnBlock extends StatelessWidget {
  const _TurnBlock({
    required this.label,
    required this.text,
    required this.finalTurn,
    required this.accent,
    required this.placeholder,
    this.emphasized = false,
  });

  final String label;
  final String text;
  final bool finalTurn;
  final Color accent;
  final String placeholder;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final visible = text.trim().isEmpty ? placeholder : text.trim();
    return AnimatedOpacity(
      opacity: finalTurn || text.isNotEmpty ? 1.0 : 0.64,
      duration: const Duration(milliseconds: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: emphasized
                  ? const Color(0xFF14202A)
                  : const Color(0xFF171A1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    visible,
                    style: TextStyle(
                      fontSize: emphasized ? 27 : 24,
                      height: 1.34,
                      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                      color: text.isEmpty ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
                if (!finalTurn && text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 4,
                    height: 25,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: Column(
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 76,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 18),
          const Text(
            'Ready to translate',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the microphone and speak naturally. Final speech appears as Input, then the local LLM translation appears directly below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.46),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSetup extends StatelessWidget {
  const _ModelSetup({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Local models required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              controller.setupStatus,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: controller.preparing
                  ? null
                  : () => controller.prepareOfflineModels(),
              child: Text(controller.preparing ? 'Installing…' : 'Install next model'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.onMic,
    required this.onSpeaker,
    required this.onReset,
    required this.onPlay,
  });

  final TranslatorController controller;
  final VoidCallback onMic;
  final VoidCallback onSpeaker;
  final VoidCallback onReset;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final micActive = controller.voiceSessionActive && !controller.micMuted;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF101214),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(
              icon: micActive ? Icons.mic_rounded : Icons.mic_none_rounded,
              active: micActive,
              enabled: controller.ready &&
                  !controller.generating &&
                  !controller.speechSynthesysSpeaking,
              onTap: onMic,
            ),
            const SizedBox(width: 12),
            _RoundButton(
              icon: Icons.volume_up_rounded,
              enabled: controller.lastOutputSide != null && !controller.generating,
              onTap: onSpeaker,
            ),
            const SizedBox(width: 12),
            _RoundButton(
              icon: Icons.refresh_rounded,
              enabled: true,
              onTap: onReset,
            ),
            const SizedBox(width: 20),
            _RoundButton(
              icon: controller.voiceSessionActive
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              active: controller.voiceSessionActive,
              enabled: controller.ready &&
                  !controller.generating &&
                  !controller.speechSynthesysSpeaking,
              large: true,
              onTap: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.active = false,
    this.large = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool active;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 70.0 : 58.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: large ? 32 : 27),
        style: IconButton.styleFrom(
          backgroundColor: active
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : const Color(0xFF1B1F23),
          foregroundColor: enabled ? Colors.white : Colors.white24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
      ),
    );
  }
}
