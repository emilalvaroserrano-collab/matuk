import 'package:flutter/material.dart';

class SetupCard extends StatelessWidget {
  const SetupCard({
    super.key,
    required this.status,
    required this.progress,
    required this.preparing,
    required this.onPrepare,
    this.error,
  });

  final String status;
  final double progress;
  final bool preparing;
  final VoidCallback onPrepare;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.translate_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Translator Mode',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (preparing) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: progress.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: preparing ? null : onPrepare,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(preparing ? 'Preparing…' : 'Prepare offline models'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
