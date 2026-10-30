import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'models.dart';

const _d2r = math.pi / 180;
const _green = Color(0xFF3BE37F);

/// Oltre questo ingrandimento il globo passa alla mappa piatta con le strade.
const globeMaxZoom = 4.6;

/// Comandi del globo dall'esterno (vai a una città, zoom, telecomando).
class GlobeController {
  _GlobeViewState? _s;

  double get lat => _s?._lat ?? 30;
  double get lng => _s?._lng ?? 12;
  double get zoom => _s?._zoom ?? 1;

  /// Sta ancora girando da solo (nessuno l'ha toccato).
  bool get spinning => _s?._spin ?? false;

  void flyTo(double lat, double lng, {double? zoom}) => _s?._flyTo(lat, lng, zoom);
  void rotateBy(double dLat, double dLng) => _s?._rotateBy(dLat, dLng);
  void zoomBy(double factor) => _s?._zoomBy(factor);

  /// La città più vicina al centro dello schermo (per il telecomando).
  Place? placeAtCenter() => _s?._placeAt(null, 44);
}

/// Il nostro globo: la Terra vera dai satelliti NASA, si gira con il dito, puntini verdi e nomi delle città.
class GlobeView extends StatefulWidget {
  const GlobeView({
    super.key,
    required this.places,
    required this.controller,
    required this.onPlace,
    required this.onDeepZoom,
    this.night = false,
    this.me,
    this.selected,
    this.initialLat = 30,
    this.initialLng = 12,
    this.initialZoom = 1,
    this.autoSpin = true,
  });

  final List<Place> places;
  final GlobeController controller;
  final ValueChanged<Place> onPlace;

  /// Ingrandito molto: si passa alla mappa piatta in questo punto.
  final void Function(double lat, double lng, double zoom) onDeepZoom;
  final bool night;
  final (double, double)? me;
  final Place? selected;
  final double initialLat, initialLng, initialZoom;
  final bool autoSpin;

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

class _Assets {
  static ui.FragmentProgram? program;
  static final Map<bool, ui.Image> images = {};
  static final Map<bool, Future<void>> _loading = {};
  static bool shaderFailed = false;

  static Future<void> load(bool night) {
    return _loading[night] ??= () async {
      try {
        program ??= await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      } catch (e) {
        shaderFailed = true;
        debugPrint('Globo senza shader: $e');
      }
      try {
        final data = await rootBundle.load(night ? 'assets/earth_night.jpg' : 'assets/earth_day.jpg');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        images[night] = (await codec.getNextFrame()).image;
      } catch (e) {
        debugPrint('Foto della Terra non caricata: $e');
      }
    }();
  }
}

class _GlobeViewState extends State<GlobeView> with SingleTickerProviderStateMixin {
  late double _lat = widget.initialLat;
  late double _lng = widget.initialLng;
  late double _zoom = widget.initialZoom;
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  // movimento
  bool _spin = true;
  Offset _vel = Offset.zero; // gradi al secondo (lng, lat)
  bool _dragging = false;
  double _startZoom = 1;
  Offset? _lastFocal;
  int _pointers = 0;

  // volo verso un punto
  (double, double, double, double, double, double)? _fly; // da lat,lng,zoom a lat,lng,zoom
  double _flyT = 0;

  // città ordinate per numero di radio (le più grandi hanno il nome per prime)
  List<Place> _ranked = const [];
  List<Place>? _rankedFor;
  Float64List _sinLat = Float64List(0), _cosLat = Float64List(0), _lngRad = Float64List(0);

  Size _size = Size.zero;

  double get _radius => math.min(_size.width, _size.height) * 0.42 * _zoom;
  Offset get _center => Offset(_size.width / 2, _size.height / 2);

  @override
  void initState() {
    super.initState();
    widget.controller._s = this;
    _spin = widget.autoSpin;
    _Assets.load(widget.night).then((_) {
      if (mounted) setState(() {});
    });
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant GlobeView old) {
    super.didUpdateWidget(old);
    widget.controller._s = this;
    if (old.night != widget.night) {
      _Assets.load(widget.night).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    if (widget.controller._s == this) widget.controller._s = null;
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _prepare() {
    if (identical(_rankedFor, widget.places)) return;
    _rankedFor = widget.places;
    _ranked = [...widget.places]..sort((a, b) => b.stations.length.compareTo(a.stations.length));
    final n = _ranked.length;
    _sinLat = Float64List(n);
    _cosLat = Float64List(n);
    _lngRad = Float64List(n);
    for (var i = 0; i < n; i++) {
      final p = _ranked[i];
      _sinLat[i] = math.sin(p.lat * _d2r);
      _cosLat[i] = math.cos(p.lat * _d2r);
      _lngRad[i] = p.lng * _d2r;
    }
  }

  void _changed() {
    _repaint.value++;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    var moving = false;
    final fly = _fly;
    if (fly != null) {
      _flyT = math.min(1, _flyT + dt / 1.1);
      final t = Curves.easeInOutCubic.transform(_flyT);
      var dl = fly.$5 - fly.$2;
      if (dl > 180) dl -= 360;
      if (dl < -180) dl += 360;
      // durante il volo si allontana un po', come un aereo
      final hop = math.sin(t * math.pi) * math.min(0.5, (dl.abs() + (fly.$4 - fly.$1).abs()) / 180);
      _lat = fly.$1 + (fly.$4 - fly.$1) * t;
      _lng = _wrap(fly.$2 + dl * t);
      _zoom = math.max(0.75, fly.$3 + (fly.$6 - fly.$3) * t - hop * fly.$3);
      if (_flyT >= 1) _fly = null;
      moving = true;
    } else if (!_dragging && _vel.distance > 0.5) {
      _lng = _wrap(_lng + _vel.dx * dt);
      _lat = (_lat + _vel.dy * dt).clamp(-80.0, 80.0);
      _vel *= math.pow(0.08, dt).toDouble(); // rallenta piano
      moving = true;
    } else if (_spin && !_dragging) {
      _lng = _wrap(_lng + 4 * dt); // gira da solo finché non lo tocchi
      moving = true;
    }
    if (moving) {
      _repaint.value++;
    } else {
      _ticker.stop();
    }
  }

  static double _wrap(double lng) {
    var l = (lng + 180) % 360;
    if (l < 0) l += 360;
    return l - 180;
  }

  void _flyTo(double lat, double lng, double? zoom) {
    _spin = false;
    _vel = Offset.zero;
    _fly = (_lat, _lng, _zoom, lat.clamp(-80.0, 80.0), lng, (zoom ?? _zoom).clamp(0.75, globeMaxZoom - 0.1));
    _flyT = 0;
    _changed();
  }

  void _rotateBy(double dLat, double dLng) {
    _spin = false;
    _lat = (_lat + dLat / _zoom).clamp(-80.0, 80.0);
    _lng = _wrap(_lng + dLng / _zoom);
    _changed();
  }

  void _zoomBy(double f) {
    _spin = false;
    _zoom = (_zoom * f).clamp(0.75, globeMaxZoom);
    _changed();
    _checkDeep();
  }

  void _checkDeep() {
    if (_zoom >= globeMaxZoom) {
      _vel = Offset.zero;
      widget.onDeepZoom(_lat, _lng, _zoom);
    }
  }

  /// Da coordinate a punto sullo schermo (null se è dietro il globo).
  Offset? _project(double lat, double lng) {
    final s0 = math.sin(_lat * _d2r), c0 = math.cos(_lat * _d2r);
    final p = lat * _d2r, l = (lng - _lng) * _d2r;
    final cosc = s0 * math.sin(p) + c0 * math.cos(p) * math.cos(l);
    if (cosc < 0) return null;
    final r = _radius;
    return Offset(_center.dx + r * math.cos(p) * math.sin(l),
        _center.dy - r * (c0 * math.sin(p) - s0 * math.cos(p) * math.cos(l)));
  }

  Place? _placeAt(Offset? pos, double maxPx) {
    _prepare();
    final at = pos ?? _center;
    final s0 = math.sin(_lat * _d2r), c0 = math.cos(_lat * _d2r);
    final r = _radius, cx = _center.dx, cy = _center.dy, l0 = _lng * _d2r;
    Place? best;
    var bestD = maxPx * maxPx;
    for (var i = 0; i < _ranked.length; i++) {
      final cl = math.cos(_lngRad[i] - l0);
      final cosc = s0 * _sinLat[i] + c0 * _cosLat[i] * cl;
      if (cosc < 0.05) continue;
      final x = cx + r * _cosLat[i] * math.sin(_lngRad[i] - l0);
      final y = cy - r * (c0 * _sinLat[i] - s0 * _cosLat[i] * cl);
      final d = (x - at.dx) * (x - at.dx) + (y - at.dy) * (y - at.dy);
      if (d < bestD) {
        bestD = d;
        best = _ranked[i];
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    _prepare();
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest;
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers = math.max(0, _pointers - 1),
        onPointerCancel: (_) => _pointers = math.max(0, _pointers - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _spin = false;
            _fly = null;
            _dragging = true;
            _vel = Offset.zero;
            _startZoom = _zoom;
            _lastFocal = d.localFocalPoint;
          },
          onScaleUpdate: (d) {
            final last = _lastFocal ?? d.localFocalPoint;
            final delta = d.localFocalPoint - last;
            _lastFocal = d.localFocalPoint;
            final degPerPx = 1 / _radius / _d2r;
            _lng = _wrap(_lng - delta.dx * degPerPx);
            _lat = (_lat + delta.dy * degPerPx).clamp(-80.0, 80.0);
            if (d.pointerCount > 1) _zoom = (_startZoom * d.scale).clamp(0.75, globeMaxZoom);
            _changed();
          },
          onScaleEnd: (d) {
            _dragging = false;
            _lastFocal = null;
            final v = d.velocity.pixelsPerSecond;
            final degPerPx = 1 / _radius / _d2r;
            if (d.pointerCount == 0 && _pointers <= 1) {
              _vel = Offset(-v.dx * degPerPx, v.dy * degPerPx);
              if (_vel.distance > 220) _vel = _vel / _vel.distance * 220;
            }
            _changed();
            _checkDeep();
          },
          onTapUp: (d) {
            final p = _placeAt(d.localPosition, 30);
            if (p != null) widget.onPlace(p);
          },
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _GlobePainter(this),
            ),
          ),
        ),
      );
    });
  }
}

class _GlobePainter extends CustomPainter {
  _GlobePainter(this.s) : super(repaint: s._repaint);
  final _GlobeViewState s;

  static final Map<String, TextPainter> _labels = {};
  static final _stars = List.generate(140, (i) {
    final r = math.Random(i * 7919);
    return (r.nextDouble(), r.nextDouble(), 0.3 + r.nextDouble() * 1.1, 0.25 + r.nextDouble() * 0.6);
  });

  TextPainter _label(String text, double size, bool big) {
    final key = '$text|$size|$big';
    return _labels[key] ??= (TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: big ? FontWeight.w700 : FontWeight.w500,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black), Shadow(blurRadius: 1, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = s.widget;
    final c = s._center;
    final r = s._radius;

    // cielo con stelle
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF05080D));
    final star = Paint();
    for (final (x, y, sz, a) in _stars) {
      star.color = Colors.white.withValues(alpha: a * 0.7);
      canvas.drawCircle(Offset(x * size.width, y * size.height), sz, star);
    }

    // atmosfera intorno al globo
    canvas.drawCircle(
      c,
      r * 1.12,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF4EA6FF).withValues(alpha: 0.45), const Color(0x004EA6FF)],
          stops: const [0.86, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.12)),
    );

    // la Terra
    final img = _Assets.images[w.night];
    final prog = _Assets.program;
    if (img != null && prog != null && !_Assets.shaderFailed) {
      final sh = prog.fragmentShader()
        ..setFloat(0, c.dx)
        ..setFloat(1, c.dy)
        ..setFloat(2, r)
        ..setFloat(3, s._lat * _d2r)
        ..setFloat(4, s._lng * _d2r)
        ..setFloat(5, w.night ? 1 : 0)
        ..setImageSampler(0, img);
      canvas.drawRect(Rect.fromCircle(center: c, radius: r + 1), Paint()..shader = sh);
    } else {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: const [Color(0xFF2D6FB0), Color(0xFF0D2A4A)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // puntini delle radio
    final n = s._ranked.length;
    if (n > 0) {
      final s0 = math.sin(s._lat * _d2r), c0 = math.cos(s._lat * _d2r), l0 = s._lng * _d2r;
      final dotScale = (0.8 + (s._zoom - 1) * 0.4).clamp(0.75, 2.2);
      final buckets = <int, List<Offset>>{};
      final xs = Float64List(n), ys = Float64List(n), vis = Float64List(n);
      for (var i = 0; i < n; i++) {
        final dl = s._lngRad[i] - l0;
        final cl = math.cos(dl);
        final cosc = s0 * s._sinLat[i] + c0 * s._cosLat[i] * cl;
        vis[i] = cosc;
        if (cosc < 0.02) continue;
        final x = c.dx + r * s._cosLat[i] * math.sin(dl);
        final y = c.dy - r * (c0 * s._sinLat[i] - s0 * s._cosLat[i] * cl);
        xs[i] = x;
        ys[i] = y;
        if (x < -20 || y < -20 || x > size.width + 20 || y > size.height + 20) continue;
        final cnt = s._ranked[i].stations.length;
        final d = (2.6 + math.min(5.0, math.log(cnt) * 1.3)) * dotScale * (0.55 + 0.45 * cosc);
        buckets.putIfAbsent((d * 2).round(), () => []).add(Offset(x, y));
      }
      final keys = buckets.keys.toList()..sort();
      final border = Paint()
        ..color = Colors.black.withValues(alpha: 0.75)
        ..strokeCap = StrokeCap.round;
      final dot = Paint()
        ..color = _green
        ..strokeCap = StrokeCap.round;
      for (final k in keys) {
        final pts = buckets[k]!;
        border.strokeWidth = k / 2 + 2.2;
        canvas.drawPoints(ui.PointMode.points, pts, border);
      }
      for (final k in keys) {
        dot.strokeWidth = k / 2;
        canvas.drawPoints(ui.PointMode.points, buckets[k]!, dot);
      }

      // nomi delle città: prima le più grandi, senza sovrapporsi
      final maxLabels = (14 * math.pow(s._zoom, 1.5)).clamp(12, 110).round();
      final placed = <Rect>[];
      final fontBase = 10.5 + math.min(2.5, (s._zoom - 1) * 0.8);
      final limit = math.min(n, 2500);
      for (var i = 0; i < limit && placed.length < maxLabels; i++) {
        if (vis[i] < 0.3) continue;
        final x = xs[i], y = ys[i];
        if (x < 0 || y < 40 || x > size.width - 30 || y > size.height - 10) continue;
        final p = s._ranked[i];
        final big = p.stations.length >= 25;
        final tp = _label(_short(p.label), big ? fontBase + 1.5 : fontBase, big);
        final rect = Rect.fromLTWH(x + 7, y - tp.height / 2, tp.width, tp.height);
        if (rect.right > size.width - 4) continue;
        final pad = rect.inflate(3);
        if (placed.any((o) => o.overlaps(pad))) continue;
        placed.add(pad);
        tp.paint(canvas, rect.topLeft);
      }
      if (_labels.length > 1500) _labels.clear();
    }

    // la città scelta
    final sel = w.selected;
    if (sel != null) {
      final p = s._project(sel.lat, sel.lng);
      if (p != null) {
        canvas.drawCircle(
            p,
            12,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.white);
      }
    }
    // tu sei qui
    final me = w.me;
    if (me != null) {
      final p = s._project(me.$1, me.$2);
      if (p != null) {
        canvas.drawCircle(p, 11, Paint()..color = const Color(0x553D8BFF));
        canvas.drawCircle(p, 7, Paint()..color = Colors.white);
        canvas.drawCircle(p, 5, Paint()..color = const Color(0xFF3D8BFF));
      }
    }
  }

  static String _short(String label) {
    final i = label.indexOf(',');
    return i > 0 ? label.substring(0, i) : label;
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => true;
}
