import 'package:flutter/material.dart';

class SetupCard extends StatelessWidget {
  const SetupCard({
    super.key,
    required this.preparing,
    required this.progress,
    required this.status,
    required this.onPrepare,
  });

  final bool preparing;
  final double progress;
  final String status;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111116),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: const Icon(Icons.graphic_eq_rounded, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Local Voice Assistant',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
              ),
              const SizedBox(height: 10),
              Text(
                'Gemma 3 1B + offline speech recognition + Supertonic 3. '
                'First setup downloads the models once; inference stays on-device afterward.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.64), height: 1.45),
              ),
              const SizedBox(height: 24),
              if (preparing) ...[
                LinearProgressIndicator(value: progress.clamp(0, 1)),
                const SizedBox(height: 12),
                Text(status, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ] else
                FilledButton.icon(
                  onPressed: onPrepare,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Prepare offline models'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
