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

kotlin_dir = root / 'android/app/src/main/kotlin/ai/eburon/matuk_translator_mode'
kotlin_dir.mkdir(parents=True, exist_ok=True)
main_activity = kotlin_dir / 'MainActivity.kt'
main_activity.write_text(r'''package ai.eburon.matuk_translator_mode

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
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
    private var activeLanguageTag: String = "en-US"

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
                        startWhenLanguageReady(languageTag, result)
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

    private fun recognitionIntent(languageTag: String): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }

    private fun startWhenLanguageReady(
        requestedLanguageTag: String,
        result: MethodChannel.Result,
    ) {
        val speechRecognizer = ensureRecognizer()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            try {
                startRecognition(requestedLanguageTag)
                result.success(mapOf("languageTag" to requestedLanguageTag))
            } catch (t: Throwable) {
                result.error("STT_START_FAILED", t.message, null)
            }
            return
        }

        val requestIntent = recognitionIntent(requestedLanguageTag)
        speechRecognizer.checkRecognitionSupport(
            requestIntent,
            mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                    val installed = bestLanguageMatch(
                        requestedLanguageTag,
                        recognitionSupport.installedOnDeviceLanguages,
                    )
                    if (installed != null) {
                        try {
                            startRecognition(installed)
                            result.success(
                                mapOf(
                                    "languageTag" to installed,
                                    "languagePack" to "installed",
                                ),
                            )
                        } catch (t: Throwable) {
                            result.error("STT_START_FAILED", t.message, null)
                        }
                        return
                    }

                    val supported = bestLanguageMatch(
                        requestedLanguageTag,
                        recognitionSupport.supportedOnDeviceLanguages,
                    )
                    val pending = bestLanguageMatch(
                        requestedLanguageTag,
                        recognitionSupport.pendingOnDeviceLanguages,
                    )

                    when {
                        supported != null -> downloadLanguagePack(supported, result)
                        pending != null -> result.error(
                            "STT_LANGUAGE_DOWNLOAD_SCHEDULED",
                            "Android is already preparing the offline speech pack for $pending.",
                            mapOf("languageTag" to pending),
                        )
                        else -> result.error(
                            "STT_LANGUAGE_UNAVAILABLE",
                            "No installed on-device speech pack is available for $requestedLanguageTag.",
                            mapOf(
                                "requested" to requestedLanguageTag,
                                "installed" to recognitionSupport.installedOnDeviceLanguages,
                                "supported" to recognitionSupport.supportedOnDeviceLanguages,
                            ),
                        )
                    }
                }

                override fun onError(error: Int) {
                    result.error(
                        "STT_SUPPORT_CHECK_FAILED",
                        "Could not check offline speech language support: ${errorMessage(error)}",
                        mapOf("code" to error),
                    )
                }
            },
        )
    }

    private fun downloadLanguagePack(
        languageTag: String,
        result: MethodChannel.Result,
    ) {
        val speechRecognizer = ensureRecognizer()
        val intent = recognitionIntent(languageTag)
        emit(
            mapOf(
                "type" to "model_download",
                "languageTag" to languageTag,
                "progress" to 0,
            ),
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            speechRecognizer.triggerModelDownload(
                intent,
                mainExecutor,
                object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {
                        emit(
                            mapOf(
                                "type" to "model_download",
                                "languageTag" to languageTag,
                                "progress" to completedPercent.coerceIn(0, 100),
                            ),
                        )
                    }

                    override fun onSuccess() {
                        emit(
                            mapOf(
                                "type" to "model_download",
                                "languageTag" to languageTag,
                                "progress" to 100,
                            ),
                        )
                        try {
                            startRecognition(languageTag)
                            result.success(
                                mapOf(
                                    "languageTag" to languageTag,
                                    "languagePack" to "downloaded",
                                ),
                            )
                        } catch (t: Throwable) {
                            result.error("STT_START_FAILED", t.message, null)
                        }
                    }

                    override fun onScheduled() {
                        result.error(
                            "STT_LANGUAGE_DOWNLOAD_SCHEDULED",
                            "Android scheduled the offline speech pack for $languageTag.",
                            mapOf("languageTag" to languageTag),
                        )
                    }

                    override fun onError(error: Int) {
                        result.error(
                            "STT_LANGUAGE_UNAVAILABLE",
                            "Android could not install the offline speech pack for $languageTag: ${errorMessage(error)}",
                            mapOf("languageTag" to languageTag, "code" to error),
                        )
                    }
                },
            )
        } else {
            speechRecognizer.triggerModelDownload(intent)
            result.error(
                "STT_LANGUAGE_DOWNLOAD_SCHEDULED",
                "Android was asked to install the offline speech pack for $languageTag.",
                mapOf("languageTag" to languageTag),
            )
        }
    }

    private fun bestLanguageMatch(requested: String, candidates: List<String>): String? {
        candidates.firstOrNull { it.equals(requested, ignoreCase = true) }?.let { return it }
        val requestedBase = requested.substringBefore('-')
        return candidates.firstOrNull {
            it.substringBefore('-').equals(requestedBase, ignoreCase = true)
        }
    }

    private fun startRecognition(languageTag: String) {
        activeLanguageTag = languageTag
        val speechRecognizer = ensureRecognizer()
        speechRecognizer.cancel()
        speechRecognizer.startListening(recognitionIntent(languageTag))
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
        SpeechRecognizer.ERROR_NETWORK -> "The offline speech pack could not be downloaded because of a network error"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "The offline speech pack download timed out"
        SpeechRecognizer.ERROR_NO_MATCH -> "No speech match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech Recognition is busy"
        SpeechRecognizer.ERROR_SERVER -> "Speech Recognition service error"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "Speech Recognition service disconnected"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
            "The device on-device recognizer does not support $activeLanguageTag"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            "The offline speech pack for $activeLanguageTag is not installed yet"
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
