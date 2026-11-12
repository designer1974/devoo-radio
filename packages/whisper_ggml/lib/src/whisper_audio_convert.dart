import 'dart:async';

import 'package:universal_io/io.dart';

/// Versione per Devoo Radio: senza FFmpeg (circa 15 MB in meno nell'APK).
/// L'app prepara già un WAV 16 kHz mono, quindi non serve convertire.
class WhisperAudioConvert {
  ///
  const WhisperAudioConvert({
    required this.audioInput,
    required this.audioOutput,
  });

  /// Input audio file
  final File audioInput;

  /// Output audio file
  final File audioOutput;

  /// Nessuna conversione: Whisper legge direttamente il file.
  Future<File?> convert() async => null;
}
