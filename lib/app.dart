import 'package:flutter/material.dart';

import 'controllers/voice_assistant_controller.dart';
import 'core/app_theme.dart';
import 'screens/chat_screen.dart';

class GemmaVoiceApp extends StatefulWidget {
  const GemmaVoiceApp({super.key});

  @override
  State<GemmaVoiceApp> createState() => _GemmaVoiceAppState();
}

class _GemmaVoiceAppState extends State<GemmaVoiceApp> {
  late final VoiceAssistantController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VoiceAssistantController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemma Voice',
      theme: AppTheme.dark(),
      home: ChatScreen(controller: _controller),
    );
  }
}
