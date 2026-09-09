import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';

class DualTranslatorScreen extends StatefulWidget {
  const DualTranslatorScreen({super.key, required this.controller});

  final TranslatorController controller;

  @override
  State<DualTranslatorScreen> createState() => _DualTranslatorScreenState();
}

class _DualTranslatorScreenState extends State<DualTranslatorScreen> {
  TranslationSide _activeSide = TranslationSide.a;
  TranslatorController get controller => widget.controller;

  Future<void> _toggleMic() async {
    if (!controller.ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Install Eb Translator, Speech Recognition, and Speech Synthesys first.',
          ),
        ),
      );
      return;
    }
    await controller.toggleMicMute(hint: _activeSide);
  }

  Future<void> _togglePlay() async {
    if (!controller.ready) {
      await controller.prepareOfflineModels();
      return;
    }
    await controller.toggleVoiceSession(hint: _activeSide);
  }

  Future<void> _replayLatest() async {
    final side = controller.lastOutputSide;
    if (side != null) await controller.replay(side);
  }

  Future<void> _copyHistory() async {
    if (controller.history.isEmpty) return;
    final out = StringBuffer();
    for (final turn in controller.history.reversed) {
      out
        ..writeln(
          '${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}',
        )
        ..writeln(turn.sourceText)
        ..writeln(turn.translatedText)
        ..writeln();
    }
    await Clipboard.setData(ClipboardData(text: out.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translation history copied.')),
    );
  }

  Future<void> _openSettings() async {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (context) => Dialog(
          backgroundColor: const Color(0xFF151719),
          insetPadding: const EdgeInsets.all(36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 860),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _SettingsPanel(
                controller: controller,
                onClose: () => Navigator.of(context).pop(),
                onCopyHistory: _copyHistory,
              ),
            ),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF151719),
      barrierColor: Colors.black.withValues(alpha: 0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.95,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _SettingsPanel(
            controller: controller,
            onClose: () => Navigator.of(context).pop(),
            onCopyHistory: _copyHistory,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFF1A1C1E),
        body: SafeArea(
          child: Column(
            children: [
              _Header(onSettings: _openSettings),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.11)),
              Expanded(
                child: _HomeStage(
                  controller: controller,
                  activeSide: _activeSide,
                  onSideChanged: (side) {
                    if (controller.voiceSessionActive || controller.busy) return;
                    setState(() => _activeSide = side);
                  },
                ),
              ),
              _BottomControls(
                controller: controller,
                onMic: _toggleMic,
                onSpeaker: _replayLatest,
                onReset: controller.clearConversation,
                onPlay: _togglePlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 20, compact ? 16 : 24, 18),
      child: Row(
        children: [
          _EburonBadge(size: compact ? 54 : 60),
          SizedBox(width: compact ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dual Translate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 20 : 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Real-time native voice translator',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    color: Colors.white.withValues(alpha: 0.52),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.tune_rounded, size: 31),
            color: Colors.white.withValues(alpha: 0.74),
          ),
        ],
      ),
    );
  }
}

class _HomeStage extends StatelessWidget {
  const _HomeStage({
    required this.controller,
    required this.activeSide,
    required this.onSideChanged,
  });

  final TranslatorController controller;
  final TranslationSide activeSide;
  final ValueChanged<TranslationSide> onSideChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tablet = constraints.maxWidth >= 700;
        final hasText = controller.textA.trim().isNotEmpty ||
            controller.textB.trim().isNotEmpty ||
            controller.history.isNotEmpty;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            tablet ? 42 : 22,
            tablet ? 26 : 18,
            tablet ? 42 : 22,
            16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(430, constraints.maxHeight - 42),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _EburonBadge(size: tablet ? 150 : 132),
                    SizedBox(height: tablet ? 34 : 28),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: tablet ? 42 : 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LanguagePair(
                      controller: controller,
                      activeSide: activeSide,
                      onSideChanged: onSideChanged,
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Text(
                        _helper,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: tablet ? 17 : 16,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.47),
                        ),
                      ),
                    ),
                    if (controller.detectedLanguageStatus.isNotEmpty &&
                        controller.voiceSessionActive) ...[
                      const SizedBox(height: 10),
                      Text(
                        controller.detectedLanguageStatus,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.40),
                        ),
                      ),
                    ],
                    if (!controller.ready || controller.preparing) ...[
                      const SizedBox(height: 26),
                      _IndependentModelInstaller(controller: controller),
                    ],
                    if (controller.error != null) ...[
                      const SizedBox(height: 18),
                      _ErrorCard(message: controller.error!),
                    ],
                    if (hasText) ...[
                      const SizedBox(height: 28),
                      _LiveConversation(controller: controller),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String get _title {
    if (controller.installingEbTranslator) return 'Installing Eb Translator';
    if (controller.installingSpeechRecognition) return 'Installing Speech Recognition';
    if (controller.installingSpeechSynthesys) return 'Installing Speech Synthesys';
    if (controller.speechSynthesysSpeaking) return 'Speaking';
    if (controller.generating) return 'Translating';
    if (controller.voiceSessionActive && controller.micMuted) return 'Session active';
    if (controller.listeningSide != null) return 'Listening';
    if (controller.voiceSessionActive) return 'Live session';
    return controller.ready ? 'Ready to translate' : 'Install local models';
  }

  String get _helper {
    if (controller.preparing) {
      return 'Only one model is installing. Let it finish, then install the next model separately.';
    }
    if (!controller.ready) {
      return 'Install the three on-device models separately below. Completed models stay installed when you close or reopen the app.';
    }
    if (controller.speechSynthesysSpeaking) {
      return 'Speech Synthesys is speaking. The microphone is paused to prevent self-hearing.';
    }
    if (controller.generating) {
      return 'Eb Translator is translating the complete sentence locally.';
    }
    if (controller.voiceSessionActive && controller.micMuted) {
      return 'Microphone muted. Tap the microphone to resume the same translation session.';
    }
    if (controller.listeningSide != null) {
      return controller.autoDetectGuestLanguage
          ? 'Listening continuously. Partial text is live; only a complete sentence is sent for translation.'
          : 'Listening continuously. Only a complete sentence is sent for translation.';
    }
    if (controller.voiceSessionActive) {
      return 'Local translation session is active.';
    }
    return 'Tap play to start a continuous session, or tap the microphone to start and control the mic.';
  }
}

class _LanguagePair extends StatelessWidget {
  const _LanguagePair({
    required this.controller,
    required this.activeSide,
    required this.onSideChanged,
  });

  final TranslatorController controller;
  final TranslationSide activeSide;
  final ValueChanged<TranslationSide> onSideChanged;

  @override
  Widget build(BuildContext context) {
    Widget language(TranslationSide side, TranslationLanguage item) {
      final active = side == activeSide && !controller.autoDetectGuestLanguage;
      return InkWell(
        onTap: controller.voiceSessionActive || controller.busy
            ? null
            : () => onSideChanged(side),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(
            item.displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: Colors.white.withValues(alpha: active ? 0.72 : 0.52),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      runSpacing: 6,
      children: [
        language(TranslationSide.a, controller.languageA),
        Icon(
          Icons.swap_horiz_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: 0.36),
        ),
        language(TranslationSide.b, controller.languageB),
      ],
    );
  }
}

class _IndependentModelInstaller extends StatelessWidget {
  const _IndependentModelInstaller({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final readyCount = <String>[
      controller.ebTranslatorStatus,
      controller.speechRecognitionStatus,
      controller.speechSynthesysStatus,
    ].where((status) => status == 'Ready').length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF15191D),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'INSTALL ON-DEVICE MODELS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.35,
                    ),
                  ),
                ),
                Text(
                  '$readyCount / 3 ready',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.56)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Install one at a time. There is no automatic chain between models.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.44),
              ),
            ),
            const SizedBox(height: 18),
            _InstallModelRow(
              label: 'Eb Translator',
              progress: controller.ebTranslatorProgress,
              status: controller.ebTranslatorStatus,
              installing: controller.installingEbTranslator,
              anotherInstalling: controller.preparing && !controller.installingEbTranslator,
              onInstall: controller.installEbTranslator,
            ),
            const SizedBox(height: 18),
            _InstallModelRow(
              label: 'Speech Recognition',
              progress: controller.speechRecognitionProgress,
              status: controller.speechRecognitionStatus,
              installing: controller.installingSpeechRecognition,
              anotherInstalling: controller.preparing && !controller.installingSpeechRecognition,
              onInstall: controller.installSpeechRecognition,
            ),
            const SizedBox(height: 18),
            _InstallModelRow(
              label: 'Speech Synthesys',
              progress: controller.speechSynthesysProgress,
              status: controller.speechSynthesysStatus,
              installing: controller.installingSpeechSynthesys,
              anotherInstalling: controller.preparing && !controller.installingSpeechSynthesys,
              onInstall: controller.installSpeechSynthesys,
            ),
            const SizedBox(height: 14),
            Text(
              controller.setupStatus,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallModelRow extends StatelessWidget {
  const _InstallModelRow({
    required this.label,
    required this.progress,
    required this.status,
    required this.installing,
    required this.anotherInstalling,
    required this.onInstall,
  });

  final String label;
  final double progress;
  final String status;
  final bool installing;
  final bool anotherInstalling;
  final Future<void> Function() onInstall;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final ready = status == 'Ready' && p >= 0.999;
    final isError = status == 'Error';
    final actionLabel = isError ? 'Retry' : p > 0 ? 'Resume' : 'Install';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    installing ? 'Installing…' : status,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isError
                          ? Theme.of(context).colorScheme.error
                          : Colors.white.withValues(alpha: 0.48),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (installing)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else if (ready)
              const Icon(Icons.check_circle_rounded, size: 22)
            else
              OutlinedButton(
                onPressed: anotherInstalling ? null : () => onInstall(),
                child: Text(actionLabel),
              ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: p, minHeight: 5),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(p * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.56),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveConversation extends StatelessWidget {
  const _LiveConversation({required this.controller});
  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    Widget card(String title, String text, IconData icon) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFF15191D),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.66)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              text.trim().isEmpty ? 'Waiting for speech…' : text,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.48,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      );
    }

    final first = card(controller.languageA.displayName, controller.textA, Icons.mic_none_rounded);
    final second = card(controller.languageB.displayName, controller.textB, Icons.volume_up_outlined);
    return Column(
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 14),
              Expanded(child: second),
            ],
          )
        else ...[
          first,
          const SizedBox(height: 12),
          second,
        ],
        if (controller.generating) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
      ],
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
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
    final compact = MediaQuery.sizeOf(context).width < 420;
    final replayEnabled = controller.lastOutputSide != null;
    final sessionEnabled = controller.ready && !controller.preparing;
    final micActive = controller.voiceSessionActive && !controller.micMuted;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, compact ? 16 : 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: _shellDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ControlButton(
                    icon: micActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                    enabled: sessionEnabled && !controller.generating && !controller.speechSynthesysSpeaking,
                    highlighted: micActive,
                    onPressed: onMic,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    icon: Icons.volume_up_rounded,
                    enabled: replayEnabled && sessionEnabled && !controller.generating,
                    onPressed: onSpeaker,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    icon: Icons.refresh_rounded,
                    enabled: sessionEnabled,
                    highlighted: true,
                    onPressed: onReset,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: _shellDecoration(),
              child: _ControlButton(
                icon: controller.voiceSessionActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
                enabled: sessionEnabled && !controller.generating && !controller.speechSynthesysSpeaking,
                highlighted: true,
                large: true,
                onPressed: onPlay,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _shellDecoration() => BoxDecoration(
        color: const Color(0xFF17191C),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.highlighted = false,
    this.large = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool highlighted;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 62.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: large ? 33 : 27),
        style: IconButton.styleFrom(
          backgroundColor: highlighted ? const Color(0xFF20272C) : const Color(0xFF1B1D20),
          foregroundColor: Colors.white.withValues(alpha: enabled ? 0.66 : 0.25),
          disabledBackgroundColor: const Color(0xFF1B1D20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.controller,
    required this.onClose,
    required this.onCopyHistory,
  });

  final TranslatorController controller;
  final VoidCallback onClose;
  final VoidCallback onCopyHistory;

  @override
  Widget build(BuildContext context) {
    final editable = !controller.voiceSessionActive && !controller.busy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 28)),
            ],
          ),
          const SizedBox(height: 20),
          _LanguageDropdown(
            label: 'Staff Language (Language 1)',
            value: controller.languageA,
            enabled: editable,
            onChanged: (value) => controller.setLanguage(TranslationSide.a, value),
          ),
          const SizedBox(height: 18),
          _LanguageDropdown(
            label: 'Guest Language (Language 2)',
            value: controller.languageB,
            enabled: editable,
            onChanged: (value) => controller.setLanguage(TranslationSide.b, value),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text('Auto-detect Guest Language', style: TextStyle(fontSize: 16)),
              ),
              Switch.adaptive(
                value: controller.autoDetectGuestLanguage,
                onChanged: editable ? controller.setAutoDetectGuestLanguage : null,
              ),
            ],
          ),
          Text(
            'Runs fully on-device. The latest detected non-Staff language becomes the Guest language automatically.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white.withValues(alpha: 0.42)),
          ),
          const SizedBox(height: 20),
          const _InfoBox(label: 'AI Voice', value: 'Speech Synthesys', icon: Icons.graphic_eq_rounded),
          const SizedBox(height: 18),
          _InfoBox(
            label: 'Conversation topic',
            value: controller.medicalMode ? 'Medical Consultation' : 'General Conversation',
            icon: Icons.folder_open_outlined,
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: true, label: Text('Medical'), icon: Icon(Icons.check_rounded)),
              ButtonSegment<bool>(value: false, label: Text('General')),
            ],
            selected: {controller.medicalMode},
            onSelectionChanged: editable
                ? (selection) => controller.setMedicalMode(selection.first)
                : null,
          ),
          const SizedBox(height: 28),
          _IndependentModelInstaller(controller: controller),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TRANSLATION HISTORY',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                ),
              ),
              Text('${controller.history.length} saved'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.history.isEmpty ? null : onCopyHistory,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.clearConversation,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Powered by Eburon AI',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
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
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 7),
          child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF20272C),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TranslationLanguage>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF20272C),
              items: translationLanguages
                  .map((item) => DropdownMenuItem<TranslationLanguage>(value: item, child: Text(item.displayName)))
                  .toList(),
              onChanged: !enabled
                  ? null
                  : (item) {
                      if (item != null) onChanged(item);
                    },
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 7),
          child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF20272C),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.68)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EburonBadge extends StatelessWidget {
  const _EburonBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF282A2C), Color(0xFF111214), Color(0xFF050506)],
          stops: [0, 0.58, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: CustomPaint(painter: _EburonMarkPainter(), size: Size.square(size)),
    );
  }
}

class _EburonMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, size.width * 0.033)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width * 0.22;
    final h = size.height * 0.40;
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((math.pi * 2 / 3) * i);
      final rect = Rect.fromCenter(
        center: Offset(0, -size.height * 0.075),
        width: w,
        height: h,
      );
      canvas.drawOval(rect, stroke);
      canvas.restore();
    }
    canvas.drawCircle(center, size.width * 0.09, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
