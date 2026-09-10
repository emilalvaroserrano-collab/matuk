import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/translator_controller.dart';
import 'core/app_theme.dart';
import 'screens/reference_style_translator_screen.dart';

class TranslatorModeApp extends StatefulWidget {
  const TranslatorModeApp({super.key});

  @override
  State<TranslatorModeApp> createState() => _TranslatorModeAppState();
}

class _TranslatorModeAppState extends State<TranslatorModeApp> {
  late final TranslatorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TranslatorController();
    unawaited(_controller.initialize());
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
      title: 'Dual Translate',
      theme: AppTheme.dark(),
      home: ReferenceStyleTranslatorScreen(controller: _controller),
    );
  }
}
