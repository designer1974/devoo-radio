import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'player.dart';
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
    super.dispose();
  }

  List<CircleMarker> _buildDots(List<Place> places) {
    if (identical(places, _drawnFor)) return _dots;
    _drawnFor = places;
    _dots = [
      for (final p in places)
        CircleMarker(
          point: LatLng(p.lat, p.lng),
          radius: 2.6 + math.min(5.0, math.log(p.stations.length) * 1.1),
          color: accent.withValues(alpha: 0.9),
          borderColor: Colors.black87,
          borderStrokeWidth: 1,
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
    showStationsSheet(
      context,
      title: '${place.flag}  ${place.label}',
      subtitle: n == 1 ? '1 radio' : '$n radio',
      stations: place.stations,
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
        final dots = _buildDots(store.places);
        final sel = _selected;
        return Stack(
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
                            else
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
