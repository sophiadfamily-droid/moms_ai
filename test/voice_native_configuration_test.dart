import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares explained voice permissions without background audio', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();

    expect(plist, contains('NSMicrophoneUsageDescription'));
    expect(plist, contains('NSSpeechRecognitionUsageDescription'));
    expect(plist, contains('Aucun enregistrement audio n’est conservé'));
    expect(plist, isNot(contains('UIBackgroundModes')));
    expect(podfile, contains('PERMISSION_MICROPHONE=1'));
    expect(podfile, contains('PERMISSION_SPEECH_RECOGNIZER=1'));
    expect(
      File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      isNot(contains('requestAuthorization')),
    );
  });

  test('Android declares only required voice access and recognizer visibility',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, contains('android.speech.RecognitionService'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_MICROPHONE')));
    expect(manifest, isNot(contains('BLUETOOTH_SCAN')));
    expect(manifest, isNot(contains('BLUETOOTH_CONNECT')));
    expect(manifest, isNot(contains('READ_MEDIA_AUDIO')));
  });

  test('voice production code has no audio persistence backend or TTS', () {
    final files = [
      File('lib/models/voice_recognition.dart'),
      File('lib/services/voice_service.dart'),
      File('lib/services/voice_recognition_coordinator.dart'),
      File('lib/widgets/voice_input_control.dart'),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    final lower = source.toLowerCase();

    expect(lower, isNot(contains('firebase')));
    expect(lower, isNot(contains('openai')));
    expect(lower, isNot(contains('websocket')));
    expect(lower, isNot(contains('texttospeech')));
    expect(lower, isNot(contains('flutter_tts')));
    expect(lower, isNot(contains('writeasbytes')));
    expect(lower, isNot(contains('sharedpreferences')));
    expect(lower, isNot(contains('audiorecorder')));
  });
}
