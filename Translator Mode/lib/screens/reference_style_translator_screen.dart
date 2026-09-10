import 'package:flutter/material.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';
import '../services/offline_stt_service.dart';

class ReferenceStyleTranslatorScreen extends StatefulWidget {
  const ReferenceStyleTranslatorScreen({super.key, required this.controller});

  final TranslatorController controller;

  @override
  State<ReferenceStyleTranslatorScreen> createState() =>
      _ReferenceStyleTranslatorScreenState();
}

class _ReferenceStyleTranslatorScreenState
    extends State<ReferenceStyleTranslatorScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF0E0F10),
          endDrawer: _SettingsDrawer(controller: controller),
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(onSettings: () => _scaffoldKey.currentState?.openEndDrawer()),
                Expanded(
                  child: controller.ready
                      ? _ConversationArea(
                          inputText: inputText,
                          translationText: translationText,
                          inputIsFinal: inputIsFinal,
                          generating: controller.generating,
                        )
                      : _ModelSetup(controller: controller),
                ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      controller.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                _ControlTray(
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              onPressed: onSettings,
              tooltip: 'Settings',
              icon: const Icon(Icons.tune_rounded),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white70,
                backgroundColor: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationArea extends StatelessWidget {
  const _ConversationArea({
    required this.inputText,
    required this.translationText,
    required this.inputIsFinal,
    required this.generating,
  });

  final String inputText;
  final String translationText;
  final bool inputIsFinal;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    if (inputText.isEmpty && translationText.isEmpty) {
      return const SizedBox.expand();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (inputText.isNotEmpty)
                _TurnBlock(
                  role: _TurnRole.input,
                  text: inputText,
                  isFinal: inputIsFinal,
                ),
              if (inputText.isNotEmpty && (translationText.isNotEmpty || generating))
                const SizedBox(height: 40),
              if (translationText.isNotEmpty || generating)
                _TurnBlock(
                  role: _TurnRole.translation,
                  text: translationText.isEmpty
                      ? 'Translating locally…'
                      : translationText,
                  isFinal: !generating && translationText.isNotEmpty,
                  placeholder: translationText.isEmpty,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TurnRole { input, translation }

class _TurnBlock extends StatelessWidget {
  const _TurnBlock({
    required this.role,
    required this.text,
    required this.isFinal,
    this.placeholder = false,
  });

  final _TurnRole role;
  final String text;
  final bool isFinal;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final accent = role == _TurnRole.input
        ? const Color(0xFF5FA8FF)
        : const Color(0xFF53D27C);
    final isTranslation = role == _TurnRole.translation;

    return AnimatedOpacity(
      opacity: isFinal ? 1 : 0.64,
      duration: const Duration(milliseconds: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role == _TurnRole.input ? 'INPUT' : 'TRANSLATION',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isTranslation
                  ? const Color(0x0D1F94FF)
                  : const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isTranslation
                    ? const Color(0x1A1F94FF)
                    : const Color(0x0DFFFFFF),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.3,
                      fontWeight: isTranslation ? FontWeight.w500 : FontWeight.w400,
                      color: placeholder ? Colors.white38 : const Color(0xFFF1F3F4),
                    ),
                  ),
                ),
                if (!isFinal && !placeholder) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F94FF),
                      borderRadius: BorderRadius.circular(4),
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

class _ControlTray extends StatelessWidget {
  const _ControlTray({
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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F10),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: OfflineSttService.micLevel,
            builder: (context, level, _) => _MicVisualizer(level: micActive ? level : 0),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                icon: micActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                active: micActive,
                enabled: controller.ready && !controller.generating && !controller.speechSynthesysSpeaking,
                onTap: onMic,
              ),
              const SizedBox(width: 12),
              _ActionButton(
                icon: controller.autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                enabled: controller.ready,
                onTap: () => controller.setAutoSpeak(!controller.autoSpeak),
              ),
              const SizedBox(width: 12),
              _ActionButton(
                icon: Icons.refresh_rounded,
                enabled: true,
                onTap: onReset,
              ),
              const SizedBox(width: 20),
              Column(
                children: [
                  _ActionButton(
                    icon: controller.voiceSessionActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    active: controller.voiceSessionActive,
                    large: true,
                    enabled: controller.ready && !controller.generating && !controller.speechSynthesysSpeaking,
                    onTap: onPlay,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Streaming',
                    style: TextStyle(
                      fontSize: 11,
                      color: controller.voiceSessionActive ? Colors.white70 : Colors.white24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MicVisualizer extends StatelessWidget {
  const _MicVisualizer({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final v = level.clamp(0.0, 1.0);
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(13, (i) {
          final center = 6;
          final distance = (i - center).abs();
          final factor = (1 - distance / 8).clamp(0.25, 1.0);
          final h = 4 + 14 * v * factor;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 2.5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: v > 0.12 ? const Color(0xFF1F94FF) : Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
    final size = large ? 66.0 : 54.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: large ? 31 : 25),
        style: IconButton.styleFrom(
          backgroundColor: active
              ? const Color(0x261F94FF)
              : const Color(0xFF1B1D20),
          foregroundColor: enabled ? Colors.white : Colors.white24,
          shape: const CircleBorder(),
          side: BorderSide(
            color: active ? const Color(0xFF1F94FF) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}

class _SettingsDrawer extends StatelessWidget {
  const _SettingsDrawer({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final locked = controller.voiceSessionActive || controller.generating || controller.preparing;

    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(300.0, 390.0),
      backgroundColor: const Color(0xFF141619),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _LanguageSelector(
                    label: 'Staff Language (Language 1)',
                    value: controller.languageA,
                    enabled: !locked,
                    onChanged: (lang) => controller.setLanguage(TranslationSide.a, lang),
                  ),
                  const SizedBox(height: 18),
                  _LanguageSelector(
                    label: 'Guest Language (Language 2)',
                    value: controller.languageB,
                    enabled: !locked && !controller.autoDetectGuestLanguage,
                    onChanged: (lang) => controller.setLanguage(TranslationSide.b, lang),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-detect Guest Language'),
                    value: controller.autoDetectGuestLanguage,
                    onChanged: locked ? null : controller.setAutoDetectGuestLanguage,
                  ),
                  const SizedBox(height: 12),
                  const Text('Translation Mode', style: TextStyle(fontWeight: FontWeight.w700)),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    groupValue: controller.medicalMode,
                    onChanged: locked ? null : (v) => controller.setMedicalMode(v ?? true),
                    title: const Text('Medical Terms'),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    groupValue: controller.medicalMode,
                    onChanged: locked ? null : (v) => controller.setMedicalMode(v ?? false),
                    title: const Text('General'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: locked ? null : () => Navigator.of(context).pop(),
                    child: const Text('Save Settings'),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Translation History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      TextButton.icon(
                        onPressed: controller.history.isEmpty ? null : controller.clearConversation,
                        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (controller.history.isEmpty)
                    const Text('No history yet. Start a translation to see it here.', style: TextStyle(color: Colors.white38))
                  else
                    ...controller.history.map(
                      (turn) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.035),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                            const SizedBox(height: 8),
                            Text('Source: ${turn.sourceText}'),
                            const SizedBox(height: 6),
                            Text('Translation: ${turn.translatedText}', style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Powered by Eburon AI', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final TranslationLanguage value;
  final bool enabled;
  final ValueChanged<TranslationLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        DropdownButtonFormField<TranslationLanguage>(
          value: value,
          isExpanded: true,
          items: translationLanguages
              .map((lang) => DropdownMenuItem(value: lang, child: Text(lang.displayName)))
              .toList(),
          onChanged: enabled ? (lang) { if (lang != null) onChanged(lang); } : null,
        ),
      ],
    );
  }
}

class _ModelSetup extends StatelessWidget {
  const _ModelSetup({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Local models required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(controller.setupStatus, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: controller.preparing ? null : controller.prepareOfflineModels,
                child: Text(controller.preparing ? 'Installing…' : 'Install next model'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
