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
manifest.write_text(text)

kts = root / 'android/app/build.gradle.kts'
if kts.exists():
    text = kts.read_text()
    text = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 26', text)
    if 'ndkVersion' in text:
        text = re.sub(
            r'ndkVersion\s*=\s*flutter\.ndkVersion',
            'ndkVersion = "27.0.12077973"',
            text,
        )
    else:
        text = text.replace(
            'compileSdk = flutter.compileSdkVersion',
            'compileSdk = flutter.compileSdkVersion\n    ndkVersion = "27.0.12077973"',
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
                r'ndkVersion\s+flutter\.ndkVersion',
                'ndkVersion "27.0.12077973"',
                text,
            )
        gradle.write_text(text)

proguard = root / 'android/app/proguard-rules.pro'
proguard.write_text('''-keep class com.write4me.llama_flutter_android.** { *; }\n-keep class ai.onnxruntime.** { *; }\n-keep class kotlin.jvm.functions.Function1\n-keepclassmembers class * implements kotlin.jvm.functions.Function1 {\n    public java.lang.Object invoke(java.lang.Object);\n}\n-keepclasseswithmembernames class * { native <methods>; }\n''')

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

print('Applied local-inference platform configuration.')
