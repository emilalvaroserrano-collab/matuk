import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/translator_controller.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';

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
      await controller.prepareOfflineModels();
      return;
    }
    if (controller.generating) {
      await controller.stopGeneration();
      return;
    }

    final stopping = controller.listeningSide == _activeSide;
    await controller.toggleListening(_activeSide);
    if (!mounted) return;

    if (stopping && controller.listeningSide == null && controller.error == null) {
      setState(() {
        _activeSide = _activeSide == TranslationSide.a
            ? TranslationSide.b
            : TranslationSide.a;
      });
    }
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
        ..writeln('${turn.sourceLanguage.displayName} → ${turn.targetLanguage.displayName}')
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
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
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
        heightFactor: 0.94,
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
      builder: (context, _) {
        return Scaffold(
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
                      if (controller.busy) return;
                      setState(() => _activeSide = side);
                    },
                  ),
                ),
                _BottomControls(
                  controller: controller,
                  onMic: _toggleMic,
                  onSpeaker: _replayLatest,
                  onReset: controller.clearConversation,
                  onPlay: _toggleMic,
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
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;
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
                      constraints: const BoxConstraints(maxWidth: 610),
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
                    if (controller.preparing) ...[
                      const SizedBox(height: 26),
                      _ProgressCard(controller: controller),
                    ],
                    if (controller.error != null) ...[
                      const SizedBox(height: 20),
                      _ErrorCard(
                        message: controller.error!,
                        onRetry: controller.ready
                            ? null
                            : controller.prepareOfflineModels,
                      ),
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
    if (controller.preparing) return 'Preparing translator';
    if (controller.listeningSide != null) return 'Listening';
    if (controller.generating) return 'Translating';
    return 'Ready to translate';
  }

  String get _helper {
    if (controller.preparing) {
      return 'The on-device models download once, then translation runs locally on this device.';
    }
    if (!controller.ready) {
      return 'Tap play to prepare the local models and start a real-time voice session.';
    }
    if (controller.listeningSide != null) {
      return 'Tap the microphone again when the sentence is complete.';
    }
    if (controller.generating) {
      return 'Eb Translator is producing the translated response on-device.';
    }
    return 'Tap play or the microphone to start a real-time voice session.';
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
      final active = side == activeSide;
      return InkWell(
        onTap: controller.busy ? null : () => onSideChanged(side),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(
            item.displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: Colors.white.withValues(alpha: active ? 0.67 : 0.48),
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

class _LiveConversation extends StatelessWidget {
  const _LiveConversation({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;

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
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;
    final replayEnabled = controller.lastOutputSide != null;

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
                    icon: controller.listeningSide != null
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    enabled: !controller.generating && !controller.preparing,
                    onPressed: onMic,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    icon: Icons.volume_up_rounded,
                    enabled: replayEnabled && !controller.preparing,
                    onPressed: onSpeaker,
                  ),
                  const SizedBox(width: 8),
                  _ControlButton(
                    icon: Icons.refresh_rounded,
                    enabled: !controller.busy,
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
                icon: !controller.ready
                    ? Icons.download_rounded
                    : controller.generating
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                enabled: !controller.preparing,
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

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.setupProgress.clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
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
                    'ON-DEVICE TRANSLATOR',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                  ),
                ),
                Text('${(p * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: p, minHeight: 4),
            const SizedBox(height: 11),
            Text(
              controller.setupStatus,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
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
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
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
            onChanged: (value) => controller.setLanguage(TranslationSide.a, value),
          ),
          const SizedBox(height: 18),
          _LanguageDropdown(
            label: 'Guest Language (Language 2)',
            value: controller.languageB,
            onChanged: (value) => controller.setLanguage(TranslationSide.b, value),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('Auto-detect Guest Language', style: TextStyle(fontSize: 16))),
              Switch.adaptive(value: false, onChanged: null),
            ],
          ),
          Text(
            'Available when multilingual Speech Recognition is integrated.',
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.42)),
          ),
          const SizedBox(height: 20),
          _InfoBox(label: 'AI Voice', value: 'Speech Synthesys', icon: Icons.graphic_eq_rounded),
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
            onSelectionChanged: controller.busy
                ? null
                : (selection) => controller.setMedicalMode(selection.first),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ON-DEVICE TRANSLATOR',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                ),
              ),
              Text(
                controller.preparing
                    ? 'downloading ${(controller.setupProgress * 100).toStringAsFixed(0)}%'
                    : controller.ready
                        ? 'ready'
                        : 'not installed',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.52)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: controller.ready ? 1 : controller.setupProgress.clamp(0, 1),
            minHeight: 4,
          ),
          const SizedBox(height: 10),
          Text(
            'Eb Translator downloads once, then translates locally on-device.',
            style: TextStyle(height: 1.45, color: Colors.white.withValues(alpha: 0.52)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.preparing ? null : controller.prepareOfflineModels,
            icon: const Icon(Icons.download_rounded),
            label: Text(controller.ready ? 'Re-check models' : 'Download models'),
          ),
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
                  onPressed: controller.busy ? null : controller.clearConversation,
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
    required this.onChanged,
  });

  final String label;
  final TranslationLanguage value;
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
                  .map(
                    (item) => DropdownMenuItem<TranslationLanguage>(
                      value: item,
                      child: Text(item.displayName),
                    ),
                  )
                  .toList(),
              onChanged: controllerBusy(context) ? null : (item) {
                if (item != null) onChanged(item);
              },
            ),
          ),
        ),
      ],
    );
  }

  bool controllerBusy(BuildContext context) => false;
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
              Expanded(child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
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
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _EburonMarkPainter(),
        size: Size.square(size),
      ),
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
