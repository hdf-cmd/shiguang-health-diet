// P4b：回复朗读。只做系统 TTS，不接语音输入；页面默认不自动播。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class TtsService {
  /// 初始化并返回中文语音是否可用。
  Future<bool> prepare();

  /// 朗读到结束才 resolve；不可用时抛 StateError。
  Future<void> speak(String text);

  Future<void> stop();
}

class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool? _ready;

  @override
  Future<bool> prepare() async {
    if (_ready != null) return _ready!;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
      final available = await _tts.isLanguageAvailable('zh-CN');
      _ready = available == true;
    } catch (_) {
      _ready = false;
    }
    return _ready!;
  }

  @override
  Future<void> speak(String text) async {
    if (!await prepare()) {
      throw StateError('系统没有可用的中文语音包');
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final ttsServiceProvider =
    Provider<TtsService>((ref) => FlutterTtsService());
