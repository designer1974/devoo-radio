import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qualità delle registrazioni (AAC in file .m4a: si apre ovunque, anche su WhatsApp e iPhone).
enum AudioQuality { voice, minimum, medium, high }

extension AudioQualityX on AudioQuality {
  int get bitrate => switch (this) {
        AudioQuality.voice => 32000,
        AudioQuality.minimum => 24000,
        AudioQuality.medium => 64000,
        AudioQuality.high => 128000,
      };
  int get outCh => this == AudioQuality.minimum ? 1 : 2;
  /// HE-AAC: suono pieno anche con pochi kbps
  bool get he => this != AudioQuality.high;
  String get label => switch (this) {
        AudioQuality.voice => 'Voce  ★ consigliata',
        AudioQuality.minimum => 'Minima',
        AudioQuality.medium => 'Media',
        AudioQuality.high => 'Alta',
      };
  String get info => switch (this) {
        AudioQuality.voice => '32 kbps stereo · ~14 MB all\'ora · parlato e musica',
        AudioQuality.minimum => '24 kbps mono · ~10 MB all\'ora · solo parlato',
        AudioQuality.medium => '64 kbps · ~28 MB all\'ora · musica',
        AudioQuality.high => '128 kbps · ~56 MB all\'ora · musica alta fedeltà',
      };
}

bool isCompressed(String path) => !path.toLowerCase().endsWith('.wav');

/// Impostazioni di registrazione salvate sul telefono.
class RecSettings {
  RecSettings._();
  static final i = RecSettings._();
  AudioQuality quality = AudioQuality.voice;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final q = p.getString('rec_quality');
      quality = AudioQuality.values.firstWhere((x) => x.name == q, orElse: () => AudioQuality.voice);
    } catch (_) {}
  }

  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('rec_quality', q.name);
    } catch (_) {}
  }
}

/// Ponte verso il codice Android (Kotlin).
class Recorder {
  static const _ch = MethodChannel('rr/recorder');
  static void Function(double)? _onProgress;
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'progress') _onProgress?.call((call.arguments as num).toDouble());
    });
  }

  static Future<T?> _withProgress<T>(Future<T?> Function() f, void Function(double)? p) async {
    _init();
    _onProgress = p;
    try {
      return await f();
    } finally {
      _onProgress = null;
    }
  }

  /// Avvia la registrazione dello stream: comprime mentre registra, in pezzi sicuri.
  static Future<void> streamStart(
      {required String url,
      required String dir,
      required String name,
      required String dst,
      required AudioQuality quality}) {
    _init();
    return _ch.invokeMethod('streamStart', {
      'url': url,
      'dir': dir,
      'name': name,
      'dst': dst,
      'bitrate': quality.bitrate,
      'outCh': quality.outCh,
      'he': quality.he,
    });
  }

  static Future<Map<String, dynamic>> streamStatus() async {
    final m = await _ch.invokeMethod<Map>('streamStatus');
    return Map<String, dynamic>.from(m ?? const {});
  }

  /// Ferma e salva. Ritorna il file M4A, o null se vuoto.
  static Future<String?> streamStop() => _ch.invokeMethod<String>('streamStop');

  /// Registrazioni interrotte da uno spegnimento: le ricompone.
  static Future<List<String>> recover(String dir) async =>
      ((await _ch.invokeMethod<List>('recover', {'dir': dir})) ?? const []).cast<String>();

  static Future<int> durationMs(String path) async =>
      (await _ch.invokeMethod<int>('duration', {'path': path})) ?? 0;

  /// WAV -> M4A (usato dall'editor).
  static Future<void> toM4a(String src, String dst, AudioQuality q,
          {void Function(double)? progress}) =>
      _withProgress(
          () => _ch.invokeMethod('toM4a', {
                'src': src,
                'dst': dst,
                'bitrate': q.bitrate,
                'outCh': q.outCh,
                'he': q.he,
              }),
          progress);

  /// M4A -> WAV (per modificare).
  static Future<void> toWav(String src, String dst, {void Function(double)? progress}) =>
      _withProgress(() => _ch.invokeMethod('toWav', {'src': src, 'dst': dst}), progress);
}
