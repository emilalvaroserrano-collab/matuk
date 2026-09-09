#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()

manifest = root / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text()
permissions = '''    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <uses-permission android:name="android.permission.INTERNET" />\n'''
if 'android.permission.RECORD_AUDIO' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + permissions,
    )

if 'android.speech.RecognitionService' not in text:
    queries = '''    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n    </queries>\n'''
    text = text.replace('<application', queries + '    <application', 1)

# Production identity and local-data defaults.
text = re.sub(
    r'android:label="[^"]+"',
    'android:label="Dual Translate"',
    text,
    count=1,
)
if 'android:allowBackup=' not in text:
    text = text.replace(
        '<application\n',
        '<application\n'
        '        android:allowBackup="false"\n'
        '        android:usesCleartextTraffic="false"\n'
        '        android:largeHeap="true"\n',
        1,
    )
manifest.write_text(text)

# Current native dependencies require NDK 28.2. Use the highest requirement.
ndk_version = '28.2.13676358'

kts = root / 'android/app/build.gradle.kts'
if kts.exists():
    text = kts.read_text()
    text = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26', text)
    if 'ndkVersion' in text:
        text = re.sub(
            r'ndkVersion\s*=\s*(?:flutter\.ndkVersion|"[^"]+")',
            f'ndkVersion = "{ndk_version}"',
            text,
        )
    else:
        text = text.replace(
            'compileSdk = flutter.compileSdkVersion',
            f'compileSdk = flutter.compileSdkVersion\n    ndkVersion = "{ndk_version}"',
        )
    kts.write_text(text)
else:
    gradle = root / 'android/app/build.gradle'
    if gradle.exists():
        text = gradle.read_text()
        text = re.sub(
            r'minSdkVersion\s+flutter\.minSdkVersion',
            'minSdkVersion 26',
            text,
        )
        if 'ndkVersion' in text:
            text = re.sub(
                r'ndkVersion\s+(?:flutter\.ndkVersion|"[^"]+")',
                f'ndkVersion "{ndk_version}"',
                text,
            )
        gradle.write_text(text)

proguard = root / 'android/app/proguard-rules.pro'
proguard.write_text('''-keep class com.write4me.llama_flutter_android.** { *; }\n-keep class kotlin.jvm.functions.Function1\n-keepclassmembers class * implements kotlin.jvm.functions.Function1 {\n    public java.lang.Object invoke(java.lang.Object);\n}\n-keepclasseswithmembernames class * { native <methods>; }\n''')

# Strict Android on-device SpeechRecognizer bridge. This deliberately uses
# createOnDeviceSpeechRecognizer (API 31+) and never falls back to the network
# recognizer. The Dart layer exposes it under the product alias Speech Recognition.
kotlin_dir = root / 'android/app/src/main/kotlin/ai/eburon/matuk_translator_mode'
kotlin_dir.mkdir(parents=True, exist_ok=True)
main_activity = kotlin_dir / 'MainActivity.kt'
main_activity.write_text(r'''package ai.eburon.matuk_translator_mode

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val methodChannelName = "ai.eburon.dual_translate/on_device_stt"
    private val eventChannelName = "ai.eburon.dual_translate/on_device_stt_events"

    private var recognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isOnDeviceRecognizerAvailable())
                    "start" -> {
                        if (!isOnDeviceRecognizerAvailable()) {
                            result.error(
                                "ON_DEVICE_STT_UNAVAILABLE",
                                "Android on-device Speech Recognition is unavailable.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            result.error(
                                "MIC_PERMISSION",
                                "Microphone permission is not granted.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val languageTag = call.argument<String>("languageTag") ?: "en-US"
                        try {
                            startRecognition(languageTag)
                            result.success(null)
                        } catch (t: Throwable) {
                            result.error("STT_START_FAILED", t.message, null)
                        }
                    }
                    "stop" -> {
                        recognizer?.stopListening()
                        result.success(null)
                    }
                    "cancel" -> {
                        recognizer?.cancel()
                        result.success(null)
                    }
                    "destroy" -> {
                        destroyRecognizer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isOnDeviceRecognizerAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
    }

    private fun ensureRecognizer(): SpeechRecognizer {
        val existing = recognizer
        if (existing != null) return existing
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            throw UnsupportedOperationException("On-device Speech Recognition requires Android 12 or newer.")
        }
        return SpeechRecognizer.createOnDeviceSpeechRecognizer(this).also { created ->
            created.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    emitStatus("ready")
                }

                override fun onBeginningOfSpeech() {
                    emitStatus("speech")
                }

                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit

                override fun onEndOfSpeech() {
                    emitStatus("end")
                }

                override fun onError(error: Int) {
                    emit(
                        mapOf(
                            "type" to "error",
                            "code" to error,
                            "message" to errorMessage(error),
                        ),
                    )
                }

                override fun onResults(results: Bundle?) {
                    emitTranscript(results, true)
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    emitTranscript(partialResults, false)
                }

                override fun onEvent(eventType: Int, params: Bundle?) = Unit
            })
            recognizer = created
        }
    }

    private fun startRecognition(languageTag: String) {
        val speechRecognizer = ensureRecognizer()
        speechRecognizer.cancel()
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
        speechRecognizer.startListening(intent)
    }

    private fun emitTranscript(bundle: Bundle?, isFinal: Boolean) {
        val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull()?.trim().orEmpty()
        emit(
            mapOf(
                "type" to "result",
                "text" to text,
                "final" to isFinal,
            ),
        )
    }

    private fun emitStatus(status: String) {
        emit(mapOf("type" to "status", "status" to status))
    }

    private fun emit(value: Map<String, Any>) {
        runOnUiThread { eventSink?.success(value) }
    }

    private fun errorMessage(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
        SpeechRecognizer.ERROR_CLIENT -> "Speech Recognition client error"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is missing"
        SpeechRecognizer.ERROR_NETWORK -> "Unexpected network error from speech service"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech service network timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "No speech match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech Recognition is busy"
        SpeechRecognizer.ERROR_SERVER -> "Speech Recognition service error"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
        else -> "Speech Recognition error $error"
    }

    private fun destroyRecognizer() {
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDestroy() {
        destroyRecognizer()
        super.onDestroy()
    }
}
''')

ios_root = root / 'ios'
if ios_root.exists():
    plist = ios_root / 'Runner/Info.plist'
    if plist.exists():
        text = plist.read_text()
        if 'NSMicrophoneUsageDescription' not in text:
            text = text.replace(
                '</dict>',
                '    <key>NSMicrophoneUsageDescription</key>\n'
                '    <string>Microphone access is used for fully local speech recognition.</string>\n'
                '</dict>',
            )
            plist.write_text(text)

    podfile = ios_root / 'Podfile'
    if podfile.exists():
        text = podfile.read_text()
        text = re.sub(
            r"^\s*#?\s*platform :ios, '[^']+'",
            "platform :ios, '16.4'",
            text,
            flags=re.MULTILINE,
        )
        if not re.search(r"^platform :ios,", text, flags=re.MULTILINE):
            text = "platform :ios, '16.4'\n" + text
        if 'use_frameworks! :linkage => :static' not in text:
            text = text.replace(
                "target 'Runner' do",
                "target 'Runner' do\n  use_frameworks! :linkage => :static",
            )
        marker = 'flutter_additional_ios_build_settings(target)'
        replacement = '''flutter_additional_ios_build_settings(target)\n    target.build_configurations.each do |config|\n      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.4'\n      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']\n      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PERMISSION_MICROPHONE=1'\n    end'''
        if marker in text and 'PERMISSION_MICROPHONE=1' not in text:
            text = text.replace(marker, replacement)
        podfile.write_text(text)

    pbx = ios_root / 'Runner.xcodeproj/project.pbxproj'
    if pbx.exists():
        text = pbx.read_text()
        text = re.sub(
            r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
            'IPHONEOS_DEPLOYMENT_TARGET = 16.4;',
            text,
        )
        pbx.write_text(text)

print('Applied production local-inference platform configuration.')
