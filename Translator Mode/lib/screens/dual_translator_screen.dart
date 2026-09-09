import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';

class DualTranslatorScreen extends StatefulWidget {
  const DualTranslatorScreen({
    super.key,
    required this.controller,
  });

  final TranslatorController controller;

  @override
  State<DualTranslatorScreen> createState() => _DualTranslatorScreenState();
}

class _DualTranslatorScreenState extends State<DualTranslatorScreen> {
  TranslationSide _activeInputSide = TranslationSide.a;

  TranslatorController get controller => widget.controller;

  Future<void> _toggleActiveMic() async {
    if (!controller.ready) {
      await controller.prepareOfflineModels();
      return;
    }

    if (controller.generating) {
      await controller.stopGeneration();
      return;
    }

    final wasStopping = controller.listeningSide == _activeInputSide;
    await controller.toggleListening(_activeInputSide);

    if (!mounted) return;
    if (wasStopping &&
        controller.listeningSide == null &&
        controller.error == null) {
      setState(() {
        _activeInputSide = _activeInputSide == TranslationSide.a
            ? TranslationSide.b
            : TranslationSide.a;
      });
    }
  }

  Future<void> _replayLatest() async {
    final side = controller.lastOutputSide;
    if (side != null) await controller.replay(side);
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF101214),
      barrierColor: Colors.black.withValues(alpha: 0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _SettingsPanel(
              controller: controller,
              onClose: () => Navigator.of(context).pop(),
              onCopyHistory: _copyHistory,
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyHistory() async {
    if (controller.history.isEmpty) return;
    final buffer = StringBuffer();
    for (final turn in controller.history.reversed) {
      buffer
        ..writeln(
          '${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}',
        )
        ..writeln(turn.sourceText)
        ..writeln(turn.translatedText)
        ..writeln();
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translation history copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        final isTablet = size.width >= 900;
        final settingsWidth = math.min(430.0, math.max(350.0, size.width * 0.34));

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        ready: controller.ready,
                        showSettingsButton: !isTablet,
                        onSettings: _openSettings,
                      ),
                      Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      if (controller.error != null)
                        _ErrorBanner(
                          message: controller.error!,
                          onDismiss: controller.clearError,
                          onRetry: controller.ready
                              ? null
                              : controller.prepareOfflineModels,
                        ),
                      Expanded(
                        child: _TranslatorStage(
                          controller: controller,
                          activeInputSide: _activeInputSide,
                          onActiveSideChanged: (side) {
                            if (controller.listeningSide != null ||
                                controller.generating) {
                              return;
                            }
                            setState(() => _activeInputSide = side);
                          },
                          onPrepare: controller.prepareOfflineModels,
                        ),
                      ),
                      _BottomControls(
                        controller: controller,
                        onMic: _toggleActiveMic,
                        onSpeaker: _replayLatest,
                        onReset: controller.clearConversation,
                        onSwap: () {
                          controller.swapLanguages();
                          setState(() {
                            _activeInputSide =
                                _activeInputSide == TranslationSide.a
                                    ? TranslationSide.b
                                    : TranslationSide.a;
                          });
                        },
                        onPlay: _toggleActiveMic,
                      ),
                    ],
                  ),
                ),
                if (isTablet)
                  SizedBox(
                    width: settingsWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0F11),
                        border: Border(
                          left: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      child: _SettingsPanel(
                        controller: controller,
                        onCopyHistory: _copyHistory,
                      ),
                    ),
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
  const _TopBar({
    required this.ready,
    required this.showSettingsButton,
    required this.onSettings,
  });

  final bool ready;
  final bool showSettingsButton;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Row(
        children: [
          const _EburonBadge(size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Dual Translate',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (ready) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.green.withValues(alpha: 0.10),
                          border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Text(
                          'LOCAL',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Real-time native voice translator',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
          ),
          if (showSettingsButton)
            IconButton(
              tooltip: 'Settings',
              onPressed: onSettings,
              icon: const Icon(Icons.tune_rounded, size: 30),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _TranslatorStage extends StatelessWidget {
  const _TranslatorStage({
    required this.controller,
    required this.activeInputSide,
    required this.onActiveSideChanged,
    required this.onPrepare,
  });

  final TranslatorController controller;
  final TranslationSide activeInputSide;
  final ValueChanged<TranslationSide> onActiveSideChanged;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final horizontalPadding = wide ? 42.0 : 20.0;
        final hasContent = controller.textA.trim().isNotEmpty ||
            controller.textB.trim().isNotEmpty ||
            controller.listeningSide != null ||
            controller.generating;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            wide ? 30 : 18,
            horizontalPadding,
            18,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(420, constraints.maxHeight - 66),
              maxWidth: 920,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EburonBadge(size: wide ? 148 : 128),
                  SizedBox(height: wide ? 30 : 24),
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: wide ? 40 : 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LanguagePairSelector(
                    controller: controller,
                    activeInputSide: activeInputSide,
                    onChanged: onActiveSideChanged,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _instruction,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: wide ? 17 : 15.5,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.47),
                    ),
                  ),
                  if (!controller.ready && !controller.preparing) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onPrepare,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Prepare on-device models'),
                    ),
                  ],
                  if (controller.preparing) ...[
                    const SizedBox(height: 26),
                    _ModelProgressCard(controller: controller),
                  ],
                  if (hasContent) ...[
                    const SizedBox(height: 28),
                    _ConversationPanels(
                      controller: controller,
                      wide: wide,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String get _headline {
    if (controller.preparing) return 'Preparing on-device translator';
    if (!controller.ready) return 'Prepare to translate';
    if (controller.listeningSide != null) return 'Listening';
    if (controller.generating) return 'Translating in real time';
    return 'Ready to translate';
  }

  String get _instruction {
    if (controller.preparing) {
      return 'Models download once. After setup, Speech Recognition, Eb Translator, and Speech Synthesys run locally.';
    }
    if (!controller.ready) {
      return 'First setup requires internet for model download. Translation works offline afterward.';
    }
    if (controller.listeningSide != null) {
      return 'Tap stop when the sentence is complete. Translation starts from the finalized transcript.';
    }
    return 'Tap a language to choose the speaker, then tap play or the microphone.';
  }
}

class _LanguagePairSelector extends StatelessWidget {
  const _LanguagePairSelector({
    required this.controller,
    required this.activeInputSide,
    required this.onChanged,
  });

  final TranslatorController controller;
  final TranslationSide activeInputSide;
  final ValueChanged<TranslationSide> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(TranslationSide side, TranslationLanguage language) {
      final active = side == activeInputSide;
      return InkWell(
        onTap: controller.generating || controller.listeningSide != null
            ? null
            : () => onChanged(side),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: active
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.52)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                const Icon(Icons.mic_rounded, size: 15),
                const SizedBox(width: 6),
              ],
              Text(
                language.displayName,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white.withValues(alpha: active ? 0.92 : 0.64),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        chip(TranslationSide.a, controller.languageA),
        Icon(
          Icons.swap_horiz_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: 0.42),
        ),
        chip(TranslationSide.b, controller.languageB),
      ],
    );
  }
}

class _ModelProgressCard extends StatelessWidget {
  const _ModelProgressCard({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final progress = controller.setupProgress.clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF171B20),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'ON-DEVICE TRANSLATOR',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 5),
            ),
            const SizedBox(height: 12),
            Text(
              controller.setupStatus,
              style: TextStyle(
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPanels extends StatelessWidget {
  const _ConversationPanels({required this.controller, required this.wide});

  final TranslatorController controller;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final a = _SpeakerPanel(
      label: 'STAFF · ${controller.languageA.displayName}',
      text: controller.textA,
      listening: controller.listeningSide == TranslationSide.a,
      onReplay: controller.textA.trim().isEmpty
          ? null
          : () => controller.replay(TranslationSide.a),
    );
    final b = _SpeakerPanel(
      label: 'GUEST · ${controller.languageB.displayName}',
      text: controller.textB,
      listening: controller.listeningSide == TranslationSide.b,
      onReplay: controller.textB.trim().isEmpty
          ? null
          : () => controller.replay(TranslationSide.b),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
        ],
      );
    }
    return Column(
      children: [a, const SizedBox(height: 14), b],
    );
  }
}

class _SpeakerPanel extends StatelessWidget {
  const _SpeakerPanel({
    required this.label,
    required this.text,
    required this.listening,
    required this.onReplay,
  });

  final String label;
  final String text;
  final bool listening;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15191E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: listening
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (listening) ...[
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 17,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Read aloud',
                onPressed: onReplay,
                icon: const Icon(Icons.volume_up_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text.trim().isEmpty
                ? (listening ? 'Listening…' : 'Waiting for speech…')
                : text,
            style: TextStyle(
              fontSize: 16,
              height: 1.48,
              color: Colors.white.withValues(alpha: text.trim().isEmpty ? 0.38 : 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.controller,
    required this.onMic,
    required this.onSpeaker,
    required this.onReset,
    required this.onSwap,
    required this.onPlay,
  });

  final TranslatorController controller;
  final VoidCallback onMic;
  final VoidCallback onSpeaker;
  final VoidCallback onReset;
  final VoidCallback onSwap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final listening = controller.listeningSide != null;
    final actionBusy = controller.generating || controller.preparing;
    final canReplay = controller.lastOutputSide != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 12,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: _controlDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ControlButton(
                    tooltip: listening ? 'Stop and translate' : 'Microphone',
                    icon: listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    onPressed: controller.preparing ? null : onMic,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    tooltip: 'Replay latest translation',
                    icon: Icons.volume_up_outlined,
                    onPressed: canReplay && !listening && !actionBusy
                        ? onSpeaker
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    tooltip: 'Swap languages',
                    icon: Icons.swap_vert_rounded,
                    onPressed: controller.busy ? null : onSwap,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    tooltip: 'Clear session',
                    icon: Icons.refresh_rounded,
                    onPressed: controller.busy ? null : onReset,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: _controlDecoration(),
              child: SizedBox(
                width: 70,
                height: 70,
                child: IconButton.filledTonal(
                  tooltip: controller.ready
                      ? (listening || controller.generating
                          ? 'Stop'
                          : 'Start voice session')
                      : 'Prepare models',
                  onPressed: onPlay,
                  icon: Icon(
                    !controller.ready
                        ? Icons.download_rounded
                        : (listening || controller.generating)
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                    size: 34,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1A232B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _controlDecoration() => BoxDecoration(
        color: const Color(0xFF111418),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 26),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF181C21),
          disabledBackgroundColor: const Color(0xFF15181C),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.controller,
    required this.onCopyHistory,
    this.onClose,
  });

  final TranslatorController controller;
  final VoidCallback onCopyHistory;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final controlsLocked = controller.listeningSide != null || controller.generating;
    final modelProgress = controller.ready
        ? 1.0
        : controller.preparing
            ? controller.setupProgress.clamp(0.0, 1.0)
            : 0.0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 30),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _LanguageDropdown(
              label: 'Staff Language (Language 1)',
              value: controller.languageA,
              enabled: !controlsLocked,
              onChanged: (language) =>
                  controller.setLanguage(TranslationSide.a, language),
            ),
            const SizedBox(height: 18),
            _LanguageDropdown(
              label: 'Guest Language (Language 2)',
              value: controller.languageB,
              enabled: !controlsLocked,
              onChanged: (language) =>
                  controller.setLanguage(TranslationSide.b, language),
            ),
            const SizedBox(height: 20),
            _SettingsSwitchRow(
              title: 'Auto-detect Guest Language',
              subtitle: 'Available when multilingual Speech Recognition is enabled.',
              value: false,
              onChanged: null,
            ),
            const SizedBox(height: 18),
            const _ReadOnlyField(
              label: 'AI Voice',
              value: 'Speech Synthesys · Default',
              icon: Icons.record_voice_over_outlined,
            ),
            const SizedBox(height: 18),
            const _ReadOnlyField(
              label: 'Conversation topic',
              value: 'Medical Consultation / General',
              icon: Icons.folder_open_outlined,
            ),
            const SizedBox(height: 18),
            SegmentedButton<bool>(
              showSelectedIcon: true,
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.medical_services_outlined),
                  label: Text('Medical'),
                ),
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('General'),
                ),
              ],
              selected: {controller.medicalMode},
              onSelectionChanged: controlsLocked
                  ? null
                  : (selection) =>
                      controller.setMedicalMode(selection.first),
            ),
            const SizedBox(height: 18),
            _SettingsSwitchRow(
              title: 'Automatic Speech Synthesys',
              subtitle: 'Read every completed translation aloud.',
              value: controller.autoSpeak,
              onChanged: controlsLocked ? null : controller.setAutoSpeak,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text(
                  'ON-DEVICE TRANSLATOR',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
                const Spacer(),
                Text(
                  controller.preparing
                      ? 'downloading ${(modelProgress * 100).toStringAsFixed(0)}%'
                      : controller.ready
                          ? 'ready'
                          : 'not installed',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.53)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: modelProgress, minHeight: 5),
            ),
            const SizedBox(height: 11),
            Text(
              'Eb Translator (~386 MB) plus Speech Recognition and Speech Synthesys download once, then run fully on-device.',
              style: TextStyle(
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.56),
              ),
            ),
            if (!controller.ready) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.preparing
                      ? null
                      : controller.prepareOfflineModels,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    controller.preparing
                        ? 'Downloading…'
                        : 'Download on-device models',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                Text(
                  'TRANSLATION HISTORY',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
                const Spacer(),
                Text(
                  '${controller.history.length} saved',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.53)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        controller.history.isEmpty ? null : onCopyHistory,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy History'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.history.isEmpty || controlsLocked
                        ? null
                        : controller.clearConversation,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
            if (controller.history.isNotEmpty) ...[
              const SizedBox(height: 18),
              _CompactHistory(history: controller.history.take(4).toList()),
            ],
            const SizedBox(height: 26),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.phone_android_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LOCAL MODE · No sign-in required',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Powered by Eburon AI',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.36),
                ),
              ),
            ),
          ],
        ),
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
    return DropdownButtonFormField<TranslationLanguage>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      dropdownColor: const Color(0xFF1C2025),
      items: translationLanguages
          .map(
            (language) => DropdownMenuItem<TranslationLanguage>(
              value: language,
              child: Text(language.displayName),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (language) {
              if (language != null) onChanged(language);
            }
          : null,
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.58)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.43),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _CompactHistory extends StatelessWidget {
  const _CompactHistory({required this.history});

  final List<TranslationTurn> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: history
          .map(
            (turn) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    turn.translatedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                  ),
                ],
              ),
            ),
          )
          .toList(),
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
          center: Alignment(-0.25, -0.35),
          radius: 0.95,
          colors: [Color(0xFF24272A), Color(0xFF050607)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.86),
          width: size >= 100 ? 2.2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: size >= 100 ? 28 : 14,
            offset: Offset(0, size >= 100 ? 12 : 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.23),
        child: CustomPaint(painter: _EburonMarkPainter()),
      ),
    );
  }
}

class _EburonMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, radius * 0.13)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);

    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 2 * math.pi / 3);
      final path = Path()
        ..moveTo(0, radius * 0.20)
        ..cubicTo(
          -radius * 0.72,
          -radius * 0.08,
          -radius * 0.48,
          -radius * 0.78,
          0,
          -radius * 0.92,
        )
        ..cubicTo(
          radius * 0.48,
          -radius * 0.78,
          radius * 0.72,
          -radius * 0.08,
          0,
          radius * 0.20,
        );
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
