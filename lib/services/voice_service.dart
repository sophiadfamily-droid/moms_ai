import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText speech = SpeechToText();

  Future<bool> init() async {
    return await speech.initialize();
  }

  Future<void> listen({
    required Function(String text) onResult,
  }) async {
    await speech.listen(
      localeId: "fr_FR",
      onResult: (result) {
        onResult(result.recognizedWords);
      },
    );
  }

  Future<void> stop() async {
    await speech.stop();
  }
}
