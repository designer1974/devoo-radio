import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'globe.dart';
import 'locate.dart';
import 'models.dart';
import 'paywall.dart';
import 'player.dart';
import 'pro.dart';
import 'search_page.dart';
import 'store.dart';
import 'widgets.dart';
import 'i18n.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  var _map = MapController();
  final _globe = GlobeController();
  bool _globeMode = true; // si parte dal globo
  LatLng _mapCenter = const LatLng(35, 12);
  double _mapZoom = 4;
  double _globeLat = 30, _globeLng = 12, _globeZoom = 1;
  bool _spun = false;
  List<Place>? _drawnFor;
  int _drawnZoom = -1;
  int _zoom = 3;
  List<CircleMarker> _dots = const [];
  Place? _selected;
  IpLocation? _me;
  bool _locating = false;
  bool _autoLocated = false;

  @override
  void initState() {
    super.initState();
    mapFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    mapFocus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  /// Puntini più grandi quando si avvicina (come Radio Garden).
  List<CircleMarker> _buildDots(List<Place> places) {
    if (identical(places, _drawnFor) && _zoom == _drawnZoom) return _dots;
    _drawnFor = places;
    _drawnZoom = _zoom;
    final scale = (0.75 + (_zoom - 2) * 0.22).clamp(0.75, 2.4);
    _dots = [
      for (final p in places)
        CircleMarker(
          point: LatLng(p.lat, p.lng),
          radius: (3.6 + math.min(6.0, math.log(p.stations.length) * 1.5)) * scale,
          color: accent.withValues(alpha: 0.92),
          borderColor: Colors.black87,
          borderStrokeWidth: 1.2,
        ),
    ];
    return _dots;
  }

  double get _minDim {
    final sz = MediaQuery.sizeOf(context);
    return math.min(sz.width, sz.height);
  }

  /// Dal globo alla mappa piatta, nello stesso punto e alla stessa grandezza.
  void _toMap(double lat, double lng, double globeZoom) {
    final radius = _minDim * 0.42 * globeZoom;
    final z = (math.log(2 * math.pi * radius / 256) / math.ln2).clamp(3.2, 14.0);
    setState(() {
      _globeMode = false;
      _spun = true;
      _mapCenter = LatLng(lat, lng);
      _mapZoom = z + 0.2;
      _map = MapController();
    });
  }

  /// Dalla mappa piatta al globo.
  void _toGlobe() {
    var lat = _mapCenter.latitude, lng = _mapCenter.longitude, z = _mapZoom;
    try {
      lat = _map.camera.center.latitude;
      lng = _map.camera.center.longitude;
      z = _map.camera.zoom;
    } catch (_) {}
    final radius = 256 * math.pow(2, z) / (2 * math.pi);
    setState(() {
      _globeMode = true;
      _spun = true;
      _globeLat = lat.clamp(-80.0, 80.0);
      _globeLng = lng;
      _globeZoom = (radius / (_minDim * 0.42)).clamp(0.9, globeMaxZoom - 0.4);
    });
  }

  /// Va in un punto: sul globo vola, sulla mappa si sposta.
  void _goTo(double lat, double lng, double mapZoom) {
    if (_globeMode) {
      final radius = 256 * math.pow(2, mapZoom) / (2 * math.pi);
      _globe.flyTo(lat, lng, zoom: math.min(globeMaxZoom - 0.3, radius / (_minDim * 0.42)));
      return;
    }
    try {
      _map.move(LatLng(lat, lng), mapZoom);
    } catch (_) {}
  }

  void _onFocus() {
    final s = mapFocus.value;
    if (s == null || !s.hasGeo) return;
    Place? place;
    for (final p in StationStore.i.places) {
      if (p.stations.any((x) => x.id == s.id)) {
        place = p;
        break;
      }
    }
    setState(() => _selected = place);
    _goTo(s.lat!, s.lng!, _globeMode ? 5 : 7);
  }

  void _onTap(LatLng pos) {
    double zoom = 3;
    try {
      zoom = _map.camera.zoom;
    } catch (_) {}
    final place = nearestPlace(StationStore.i.places, pos.latitude, pos.longitude, zoom);
    if (place == null) return;
    setState(() => _selected = place);
    _openPlace(place);
  }

  void _openPlace(Place place) {
    final n = place.stations.length;
    final first = place.stations.first;
    final code = place.countryCode;
    showStationsSheet(
      context,
      title: '${place.flag}  ${place.label}',
      subtitle: n == 1 ? '1 radio qui' : '$n radio qui',
      stations: place.stations,
      action: code.length != 2
          ? null
          : (ctx) {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CountryPage(country: Country(code, first.country, 0))));
            },
      actionLabel: 'Tutte le radio di ${Country(code, first.country, 0).displayName}',
    );
  }

  // ---------- TV: telecomando ----------
  final _focus = FocusNode(debugLabel: 'mappa');

  void _pan(double dx, double dy) {
    if (_globeMode) {
      _globe.rotateBy(-dy * 8, dx * 8);
      return;
    }
    try {
      final c = _map.camera;
      final k = 256 * math.pow(2, c.zoom) / 360; // pixel per grado
      final step = 140 / k;
      final lat = (c.center.latitude - dy * step * math.cos(c.center.latitude * math.pi / 180)).clamp(-80.0, 80.0);
      final lng = normalizeLng(c.center.longitude + dx * step);
      _map.move(LatLng(lat, lng), c.zoom);
    } catch (_) {}
  }

  void _zoomBy(double d) {
    if (_globeMode) {
      _globe.zoomBy(d > 0 ? 1.45 : 1 / 1.45);
      return;
    }
    try {
      final c = _map.camera;
      _map.move(c.center, (c.zoom + d).clamp(1.5, 14.0));
    } catch (_) {}
  }

  /// OK sul telecomando: apre la città sotto il mirino, altrimenti ingrandisce.
  void _select() {
    if (_globeMode) {
      final p = _globe.placeAtCenter();
      if (p != null) {
        setState(() => _selected = p);
        _openPlace(p);
      } else {
        _zoomBy(1);
      }
      return;
    }
    try {
      final c = _map.camera;
      final p = nearestPlace(StationStore.i.places, c.center.latitude, c.center.longitude, c.zoom, maxPx: 40);
      if (p != null) {
        setState(() => _selected = p);
        _openPlace(p);
      } else {
        _zoomBy(1);
      }
    } catch (_) {}
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) { _pan(-1, 0); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowRight) { _pan(1, 0); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowUp) { _pan(0, -1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowDown) { _pan(0, 1); return KeyEventResult.handled; }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _select();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _zoomBy(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract ||
        k == LogicalKeyboardKey.mediaRewind) {
      _zoomBy(-1);
      return KeyEventResult.handled;
    }
    // Indietro: esce dalla mappa e va ai pulsanti in basso
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Trova la città dell'utente dall'IP, sposta la mappa e mostra le radio vicine.
  Future<void> _locate({bool auto = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    if (!auto) {
      messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Cerco dove sei…'))));
    }
    final loc = await locateByIp();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (loc != null) _me = loc;
    });
    if (loc == null) {
      if (!auto) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Posizione non trovata. Controlla internet e riprova.')));
      }
      return;
    }
    // all'apertura il globo gira un po' e poi si ferma su di te
    if (!(auto && _globeMode && _globe.spinning)) {
      _goTo(loc.lat, loc.lng, auto ? 4 : 6);
    } else {
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _globeMode && _globe.spinning) _goTo(loc.lat, loc.lng, 3.6);
      });
    }
    messenger.hideCurrentSnackBar();
    if (!auto) {
      messenger.showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Sei a {}').replaceFirst('{}', loc.label))));
      _openNearby(loc);
    }
  }

  /// Le radio più vicine all'utente, dalla più vicina.
  void _openNearby(IpLocation loc) {
    final places = StationStore.i.places;
    if (places.isEmpty) return;
    double d(Place p) {
      final dl = (p.lat - loc.lat), dg = (p.lng - loc.lng) * math.cos(loc.lat * math.pi / 180);
      return dl * dl + dg * dg;
    }
    final near = [...places]..sort((a, b) => d(a).compareTo(d(b)));
    final stations = [for (final p in near.take(25)) ...p.stations].take(60).toList();
    showStationsSheet(
      context,
      title: '📍 ${tr('Radio vicino a te')}',
      subtitle: loc.label,
      stations: stations,
    );
  }

  void _surprise() {
    final s = StationStore.i.random();
    if (s == null) return;
    mapFocus.value = null;
    mapFocus.value = s;
    RadioPlayer.i.play(s);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([StationStore.i, Library.i]),
      builder: (context, _) {
        final store = StationStore.i;
        if (!_autoLocated && store.places.isNotEmpty) {
          _autoLocated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && mapFocus.value == null) _locate(auto: true);
          });
        }
        final dots = _buildDots(store.places);
        final sel = _selected;
        final tv = Pro.i.isTv;
        final stack = Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _globeMode
                  ? GlobeView(
              key: ValueKey('globo$_globeLat$_globeLng$_globeZoom'),
              places: store.places,
              controller: _globe,
              night: Library.i.mapStyle == 1,
              me: _me == null ? null : (_me!.lat, _me!.lng),
              selected: sel,
              initialLat: _globeLat,
              initialLng: _globeLng,
              initialZoom: _globeZoom,
              autoSpin: !_spun,
              onPlace: (p) {
                _spun = true;
                setState(() => _selected = p);
                _openPlace(p);
              },
              onDeepZoom: _toMap,
            )
                  : FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
                minZoom: 2.5,
                maxZoom: 14,
                backgroundColor: const Color(0xFF0B0F14),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, pos) => _onTap(pos),
                onPositionChanged: (camera, gesture) {
                  _mapCenter = camera.center;
                  _mapZoom = camera.zoom;
                  // allontanandosi molto si torna al globo
                  if (gesture && camera.zoom < 2.9) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_globeMode) _toGlobe();
                    });
                    return;
                  }
                  final z = camera.zoom.round();
                  if (z != _zoom) setState(() => _zoom = z);
                },
              ),
              children: [
                ..._tiles(Library.i.mapStyle),
                CircleLayer(circles: dots),
                if (_me != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: LatLng(_me!.lat, _me!.lng),
                      radius: 9,
                      color: const Color(0xFF3D8BFF),
                      borderColor: Colors.white,
                      borderStrokeWidth: 3,
                    ),
                  ]),
                if (sel != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: LatLng(sel.lat, sel.lng),
                      radius: 11,
                      color: Colors.white.withValues(alpha: 0.15),
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.5,
                    ),
                  ]),
              ],
            ),
            ),
            // In alto: titolo e stato
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: scheme.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                        child: Row(
                          children: [
                            const Icon(Icons.public, color: accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Devoo Radio',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800, fontSize: 17)),
                                  Text(
                                    store.stations.isEmpty
                                        ? (store.loading
                                            ? 'Scarico le radio del mondo… ${(store.progress * 100).round()}%'
                                            : 'Tocca un puntino verde')
                                        : '${_fmt(store.stations.length)} radio · ${_fmt(store.places.length)} città${store.loading ? ' · scarico…' : ''}',
                                    style: TextStyle(
                                        fontSize: 12, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (store.loading)
                              const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else
                              const LangButton(),
                            if (!store.loading && !Pro.i.isPro)
                              IconButton(
                                tooltip: 'Passa a Pro',
                                icon: const Icon(Icons.workspace_premium_outlined, color: accent),
                                onPressed: () => openPaywall(context),
                              ),
                            if (!store.loading)
                              IconButton(
                                tooltip: 'Aggiorna le radio',
                                icon: const Icon(Icons.refresh),
                                onPressed: store.refresh,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (store.error != null) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: const Icon(Icons.wifi_off),
                          title: Text(store.error!),
                          trailing: TextButton(
                              onPressed: store.refresh, child: const Text('Riprova')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 150,
              child: FloatingActionButton.small(
                heroTag: 'me',
                tooltip: tr('Dove sono'),
                onPressed: _locating
                    ? null
                    : () {
                        final me = _me;
                        if (me != null && !_locating) _goTo(me.lat, me.lng, 6);
                        _locate();
                      },
                child: _locating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 200,
              child: FloatingActionButton.small(
                heroTag: 'globe',
                tooltip: _globeMode ? tr('Mappa') : tr('Globo'),
                onPressed: () => _globeMode
                    ? _toMap(_globe.lat, _globe.lng, math.max(_globe.zoom, 2.2))
                    : _toGlobe(),
                child: Icon(_globeMode ? Icons.map_outlined : Icons.public),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 100,
              child: FloatingActionButton.small(
                heroTag: 'style',
                tooltip: 'Cambia mappa',
                onPressed: () => Library.i.mapStyle = Library.i.mapStyle == 0 ? 1 : 0,
                child: Icon(Library.i.mapStyle == 0 ? Icons.dark_mode : Icons.satellite_alt),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 30,
              child: FloatingActionButton.extended(
                heroTag: 'surprise',
                backgroundColor: accent,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.shuffle),
                label: const Text('Sorprendimi'),
                onPressed: store.stations.isEmpty ? null : _surprise,
              ),
            ),
            Positioned(
              left: 8,
              bottom: 4,
              child: Text(
                  _globeMode
                      ? 'Terra © NASA Blue Marble · radio-browser.info'
                      : 'Mappa © Esri, Maxar, Earthstar Geographics · radio-browser.info',
                  style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
            ),
          ],
        );
        if (!tv) return stack;
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: ListenableBuilder(
            listenable: _focus,
            builder: (_, child) => Stack(children: [
              child!,
              // mirino al centro, come Radio Garden
              IgnorePointer(
                child: Center(
                  child: Icon(Icons.add_circle_outline,
                      size: 44, color: _focus.hasFocus ? Colors.white : Colors.white38),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 24,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _focus.hasFocus
                          ? 'Frecce: muovi · OK: apri la città · CH+ / CH−: zoom · Indietro: menu'
                          : 'Premi su per tornare alla mappa',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ]),
            child: stack,
          ),
        );
      },
    );
  }
}

const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';

/// Satellite (tipo Google Earth) con confini e nomi, oppure mappa scura. Gratis, senza chiave.
List<Widget> _tiles(int style) {
  const ua = 'com.designer1974.devoo_radio';
  if (style == 1) {
    return [
      TileLayer(
        urlTemplate: '$_esri/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: ua,
        maxNativeZoom: 16,
      ),
      TileLayer(
        urlTemplate: '$_esri/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: ua,
        maxNativeZoom: 16,
      ),
    ];
  }
  return [
    TileLayer(
      urlTemplate: '$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: ua,
      maxNativeZoom: 18,
    ),
    TileLayer(
      urlTemplate: '$_esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: ua,
      maxNativeZoom: 18,
    ),
  ];
}

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
