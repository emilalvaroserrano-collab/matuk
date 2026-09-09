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

# lib_llama_cpp_android 0.7.3 requires Android API 28. Do not override the
# library manifest with a lower value because that can produce runtime crashes.
min_sdk = 28

kts = root / 'android/app/build.gradle.kts'
if kts.exists():
    text = kts.read_text()
    text = re.sub(
        r'minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)',
        f'minSdk = {min_sdk}',
        text,
    )
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
            r'minSdkVersion\s+(?:flutter\.minSdkVersion|\d+)',
            f'minSdkVersion {min_sdk}',
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
proguard.write_text('''-keepclasseswithmembernames class * { native <methods>; }\n''')

# Speech Synthesys generates PCM in Flutter. Android plays that PCM directly
# through AudioTrack rather than writing a WAV and asking MediaPlayer to set a
# file source. This avoids MEDIA_ERROR_SYSTEM / Failed to set source failures.
main_activity = (
    root
    / 'android/app/src/main/kotlin/ai/eburon/matuk_translator_mode/MainActivity.kt'
)
main_activity.parent.mkdir(parents=True, exist_ok=True)
main_activity.write_text(r'''package ai.eburon.matuk_translator_mode

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val audioExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var currentTrack: AudioTrack? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.eburon.dual_translate/audio_output",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playPcm16" -> {
                    val sampleRate = call.argument<Int>("sampleRate")
                    val pcm = call.argument<ByteArray>("pcm")
                    if (sampleRate == null || sampleRate <= 0 || pcm == null || pcm.isEmpty()) {
                        result.error("AUDIO_BAD_INPUT", "Invalid PCM audio payload", null)
                        return@setMethodCallHandler
                    }
                    audioExecutor.execute {
                        try {
                            playPcm16Blocking(pcm, sampleRate)
                            runOnUiThread { result.success(null) }
                        } catch (t: Throwable) {
                            runOnUiThread {
                                result.error(
                                    "AUDIO_TRACK_ERROR",
                                    t.message ?: t.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                }
                "stopPcm" -> {
                    stopCurrentTrack()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playPcm16Blocking(pcm: ByteArray, sampleRate: Int) {
        stopCurrentTrack()

        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            throw IllegalStateException("Unsupported Speech Synthesys sample rate: $sampleRate")
        }

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(minBuffer, 8192))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            throw IllegalStateException("Android AudioTrack failed to initialize")
        }

        currentTrack = track
        try {
            track.play()
            var offset = 0
            while (offset < pcm.size && currentTrack === track) {
                val written = track.write(
                    pcm,
                    offset,
                    pcm.size - offset,
                    AudioTrack.WRITE_BLOCKING,
                )
                if (written < 0) {
                    throw IllegalStateException("Android AudioTrack write failed: $written")
                }
                if (written == 0) {
                    Thread.yield()
                } else {
                    offset += written
                }
            }
        } finally {
            if (currentTrack === track) currentTrack = null
            try { track.stop() } catch (_: Throwable) {}
            try { track.flush() } catch (_: Throwable) {}
            try { track.release() } catch (_: Throwable) {}
        }
    }

    private fun stopCurrentTrack() {
        val track = currentTrack ?: return
        currentTrack = null
        try { track.pause() } catch (_: Throwable) {}
        try { track.flush() } catch (_: Throwable) {}
        try { track.stop() } catch (_: Throwable) {}
        try { track.release() } catch (_: Throwable) {}
    }

    override fun onDestroy() {
        stopCurrentTrack()
        audioExecutor.shutdownNow()
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
                '    <string>Microphone access is used for fully local whisper.cpp speech recognition.</string>\n'
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
