import 'package:flutter/material.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.listening,
    required this.generating,
    required this.transcript,
    required this.onSend,
    required this.onMic,
    required this.onStop,
  });

  final bool listening;
  final bool generating;
  final String transcript;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;
  final VoidCallback onStop;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onSend(text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.listening)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.transcript.isEmpty
                          ? 'Listening…'
                          : widget.transcript),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: widget.listening ? 'Stop and send' : 'Voice input',
                  onPressed: widget.generating ? null : widget.onMic,
                  icon: Icon(widget.listening ? Icons.stop_rounded : Icons.mic_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.listening && !widget.generating,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message Gemma…',
                      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: widget.generating ? 'Stop generation' : 'Send',
                  onPressed: widget.generating
                      ? widget.onStop
                      : (_controller.text.trim().isEmpty ? null : _send),
                  icon: Icon(widget.generating ? Icons.stop_rounded : Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
