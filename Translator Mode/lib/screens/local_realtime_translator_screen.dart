import 'package:flutter/material.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';
import '../services/offline_stt_service.dart';

class LocalRealtimeTranslatorScreen extends StatefulWidget {
  const LocalRealtimeTranslatorScreen({super.key, required this.controller});

  final TranslatorController controller;

  @override
  State<LocalRealtimeTranslatorScreen> createState() =>
      _LocalRealtimeTranslatorScreenState();
}

class _LocalRealtimeTranslatorScreenState
    extends State<LocalRealtimeTranslatorScreen> {
  TranslatorController get controller => widget.controller;
  TranslationSide _activeSide = TranslationSide.a;
  String _lastHeard = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(_rememberTranscript);
  }

  @override
  void dispose() {
    controller.removeListener(_rememberTranscript);
    super.dispose();
  }

  void _rememberTranscript() {
    final live = controller.liveTranscript.trim();
    if (live.isNotEmpty) _lastHeard = live;
  }

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

  ({String input, String translation, bool inputFinal}) _visibleTurn() {
    final latest = controller.history.isEmpty ? null : controller.history.first;
    final live = controller.liveTranscript.trim();

    if (controller.listeningSide != null && live.isNotEmpty) {
      return (input: live, translation: '', inputFinal: false);
    }

    if (controller.generating || controller.speechSynthesysSpeaking) {
      final frozen = _lastHeard.trim();
      final a = controller.textA.trim();
      final b = controller.textB.trim();
      if (frozen.isNotEmpty) {
        final translation = a == frozen ? b : (b == frozen ? a : _bestDifferent(frozen, a, b));
        return (input: frozen, translation: translation, inputFinal: true);
      }
    }

    if (latest != null) {
      return (
        input: latest.sourceText.trim(),
        translation: latest.translatedText.trim(),
        inputFinal: true,
      );
    }

    final a = controller.textA.trim();
    final b = controller.textB.trim();
    return (input: a.isNotEmpty ? a : b, translation: '', inputFinal: false);
  }

  String _bestDifferent(String source, String a, String b) {
    if (a.isEmpty && b.isEmpty) return '';
    if (a == source) return b;
    if (b == source) return a;
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return a.length == source.length ? b : a;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final turn = _visibleTurn();
        final hasTurn = turn.input.isNotEmpty || turn.translation.isNotEmpty;
        return Scaffold(
          backgroundColor: const Color(0xFF101214),
          body: SafeArea(
            child: Column(
              children: [
                _Header(status: controller.setupStatus),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LanguageRow(
                              controller: controller,
                              activeSide: _activeSide,
                              onChanged: (side) {
                                if (controller.voiceSessionActive || controller.busy) return;
                                setState(() => _activeSide = side);
                              },
                            ),
                            const SizedBox(height: 28),
                            if (!controller.ready || controller.preparing)
                              _ModelSetup(controller: controller)
                            else if (!hasTurn)
                              const _EmptyState()
                            else ...[
                              _TextBlock(
                                label: turn.inputFinal ? 'Final transcription' : 'Transcription',
                                text: turn.input,
                                placeholder: 'Listening…',
                                accent: const Color(0xFF5FA8FF),
                                emphasized: false,
                                active: !turn.inputFinal,
                              ),
                              const SizedBox(height: 14),
                              _TextBlock(
                                label: 'Translation',
                                text: turn.translation,
                                placeholder: controller.generating
                                    ? 'Translating locally…'
                                    : 'Waiting for translation…',
                                accent: const Color(0xFF69D391),
                                emphasized: true,
                                active: controller.generating,
                              ),
                            ],
                            if (controller.error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                controller.error!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                  onReset: () {
                    _lastHeard = '';
                    controller.clearConversation();
                  },
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
  const _Header({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dual Translate', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Local STT · Local LLM · Local TTS', style: TextStyle(fontSize: 13, color: Colors.white54)),
              ],
            ),
          ),
          Flexible(
            child: Text(
              status,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.42)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.controller, required this.activeSide, required this.onChanged});
  final TranslatorController controller;
  final TranslationSide activeSide;
  final ValueChanged<TranslationSide> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(TranslationSide side, TranslationLanguage language) => ChoiceChip(
          selected: activeSide == side,
          onSelected: (_) => onChanged(side),
          label: Text(language.displayName),
        );
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

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.label,
    required this.text,
    required this.placeholder,
    required this.accent,
    required this.emphasized,
    required this.active,
  });
  final String label;
  final String text;
  final String placeholder;
  final Color accent;
  final bool emphasized;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final value = text.trim().isEmpty ? placeholder : text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.45),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: emphasized ? const Color(0xFF14202A) : const Color(0xFF171A1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: active ? 0.34 : 0.16), width: active ? 1.4 : 1),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: emphasized ? 27 : 24,
              height: 1.34,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              color: text.trim().isEmpty ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 88),
      child: Column(
        children: [
          Icon(Icons.graphic_eq_rounded, size: 76, color: Colors.white24),
          SizedBox(height: 18),
          Text('Ready to translate', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            'Speak naturally. Final transcription stays visible, and the local translation appears directly below it.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5, color: Colors.white54),
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
            const Text('Local models required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(controller.setupStatus, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: controller.preparing ? null : () => controller.prepareOfflineModels(),
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
    final micActive = controller.voiceSessionActive && !controller.micMuted && controller.listeningSide != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF101214),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MicActivityButton(
              active: micActive,
              enabled: controller.ready && !controller.generating && !controller.speechSynthesysSpeaking,
              onTap: onMic,
            ),
            const SizedBox(width: 12),
            _RoundButton(
              icon: Icons.volume_up_rounded,
              enabled: controller.lastOutputSide != null && !controller.generating,
              onTap: onSpeaker,
            ),
            const SizedBox(width: 12),
            _RoundButton(icon: Icons.refresh_rounded, enabled: true, onTap: onReset),
            const SizedBox(width: 20),
            _RoundButton(
              icon: controller.voiceSessionActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
              active: controller.voiceSessionActive,
              enabled: controller.ready && !controller.generating && !controller.speechSynthesysSpeaking,
              large: true,
              onTap: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _MicActivityButton extends StatelessWidget {
  const _MicActivityButton({required this.active, required this.enabled, required this.onTap});
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: OfflineSttService.micLevel,
      builder: (context, level, _) {
        final normalized = active ? level.clamp(0.0, 1.0) : 0.0;
        return SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                width: 42 + (12 * normalized),
                height: 42 + (12 * normalized),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10 + 0.20 * normalized),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.24 + 0.46 * normalized),
                    width: 1.5 + 1.5 * normalized,
                  ),
                ),
              ),
              if (active)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final factors = [0.62, 1.0, 0.76];
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 3,
                      height: 6 + 17 * normalized * factors[i],
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                )
              else
                Icon(Icons.mic_none_rounded, size: 27, color: enabled ? Colors.white : Colors.white24),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: enabled ? onTap : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.enabled, required this.onTap, this.active = false, this.large = false});
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
