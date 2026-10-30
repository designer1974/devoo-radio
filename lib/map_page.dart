import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'paywall.dart';
import 'player.dart';
import 'pro.dart';
import 'search_page.dart';
import 'store.dart';
import 'widgets.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  List<Place>? _drawnFor;
  int _drawnZoom = -1;
  int _zoom = 3;
  List<CircleMarker> _dots = const [];
  Place? _selected;

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
    try {
      _map.move(LatLng(s.lat!, s.lng!), 7);
    } catch (_) {}
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
    try {
      final c = _map.camera;
      _map.move(c.center, (c.zoom + d).clamp(1.5, 14.0));
    } catch (_) {}
  }

  /// OK sul telecomando: apre la città sotto il mirino, altrimenti ingrandisce.
  void _select() {
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
        final dots = _buildDots(store.places);
        final sel = _selected;
        final tv = Pro.i.isTv;
        final stack = Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(35, 12),
                initialZoom: 2.6,
                minZoom: 1.5,
                maxZoom: 14,
                backgroundColor: const Color(0xFF0B0F14),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, pos) => _onTap(pos),
                onPositionChanged: (camera, _) {
                  final z = camera.zoom.round();
                  if (z != _zoom) setState(() => _zoom = z);
                },
              ),
              children: [
                ..._tiles(Library.i.mapStyle),
                CircleLayer(circles: dots),
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
                            else if (!Pro.i.isPro)
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
              child: Text('Mappa © Esri, Maxar, Earthstar Geographics · radio-browser.info',
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
