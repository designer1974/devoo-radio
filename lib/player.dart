import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';
import 'models.dart';
import 'store.dart';

/// Il lettore radio: suona anche a schermo spento, con i controlli nella notifica.
class RadioPlayer extends ChangeNotifier {
  RadioPlayer._() {
    _player.playerStateStream.listen((_) => notifyListeners(), onError: (Object _) {});
    _player.icyMetadataStream.listen((m) {
      final t = m?.info?.title?.trim();
      final v = (t == null || t.isEmpty || t == '-') ? null : t;
      if (v != nowPlaying) {
        nowPlaying = v;
        notifyListeners();
      }
    }, onError: (Object _) {});
    _player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) {
      final s = current;
      if (s != null) _fail(s);
    });
  }
  static final i = RadioPlayer._();

  final AudioPlayer _player = AudioPlayer(
    // parte appena ha 0,6 s di audio invece di aspettare 2,5 s
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        bufferForPlaybackDuration: Duration(milliseconds: 600),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
      ),
    ),
  );
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  Station? current;
  String? nowPlaying;
  int _seq = 0;
  Timer? _sleepTimer;
  DateTime? sleepAt;

  ProcessingState get _state => _player.processingState;

  /// L'utente vuole ascoltare (anche mentre si collega).
  bool get wantsPlay => current != null && _player.playing;

  bool get isPlaying => current != null && _player.playing && _state != ProcessingState.idle;

  bool get isBuffering =>
      current != null &&
      _player.playing &&
      (_state == ProcessingState.loading || _state == ProcessingState.buffering);

  bool isCurrent(Station s) => current?.id == s.id;

  Future<void> play(Station s) async {
    final seq = ++_seq;
    current = s;
    nowPlaying = null;
    notifyListeners();
    Library.i.addRecent(s);
    RadioApi.i.click(s.id);
    try {
      final art = s.hasLogo ? Uri.tryParse(s.favicon) : null;
      await _player
          .setAudioSource(AudioSource.uri(
            Uri.parse(s.url),
            tag: MediaItem(
              id: s.id,
              title: s.name,
              album: '${s.flag} ${s.place}',
              artist: 'Devoo Radio',
              artUri: art,
            ),
          ))
          .timeout(const Duration(seconds: 25));
      if (seq != _seq) return;
      unawaited(_player.play().catchError((Object _) {}));
    } catch (_) {
      if (seq != _seq) return;
      _fail(s);
    }
  }

  void _fail(Station s) {
    _errors.add('«${s.name}» non risponde. Prova un\'altra radio.');
    _player.stop().catchError((Object _) {});
    notifyListeners();
  }

  /// Per una radio "pausa" vuol dire fermare: alla ripresa si riascolta in diretta.
  Future<void> toggle() async {
    final s = current;
    if (s == null) return;
    if (_player.playing) {
      await stop();
    } else {
      await play(s);
    }
  }

  Future<void> stop() async {
    _seq++;
    try {
      await _player.stop();
    } catch (_) {}
    notifyListeners();
  }

  void setSleep(Duration? d) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        sleepAt = null;
        stop();
      });
    }
    notifyListeners();
  }
}
