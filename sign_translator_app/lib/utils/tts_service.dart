import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final FlutterTts _tts = FlutterTts();

  static Future init() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  static Future speak(String text) async {
    await _tts.stop(); // prevent overlap
    await _tts.speak(text);
  }
}