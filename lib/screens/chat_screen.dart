import 'package:flutter/material.dart';

import '../controllers/voice_assistant_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/setup_card.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller});

  final VoiceAssistantController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.controller.initialize();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('Gemma Voice', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (c.ready)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('LOCAL', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            onPressed: c.messages.isEmpty || c.generating ? null : c.clearChat,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (c.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(c.error!),
            ),
          Expanded(
            child: !c.ready
                ? SetupCard(
                    preparing: c.preparing,
                    progress: c.setupProgress,
                    status: c.setupStatus,
                    onPrepare: c.prepareOfflineModels,
                  )
                : c.messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: c.messages.length,
                        itemBuilder: (context, index) => ChatBubble(message: c.messages[index]),
                      ),
          ),
          if (c.ready)
            MessageComposer(
              listening: c.listening,
              generating: c.generating,
              transcript: c.transcript,
              onSend: c.send,
              onMic: c.toggleListening,
              onStop: c.stopGeneration,
            ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.tertiary,
                  ],
                ),
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 42, color: Colors.white),
            ),
            const SizedBox(height: 22),
            const Text('How can I help?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Speak or type. STT, Gemma inference, and TTS all run locally after first setup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.56), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
