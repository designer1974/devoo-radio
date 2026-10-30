import 'package:flutter/material.dart';

import 'models.dart';
import 'player.dart';
import 'recording.dart';
import 'store.dart';

/// Navigazione condivisa: scheda attiva e stazione da mostrare sulla mappa.
final tabIndex = ValueNotifier<int>(0);
final mapFocus = ValueNotifier<Station?>(null);

void showOnMap(BuildContext context, Station s) {
  if (!s.hasGeo) return;
  Navigator.of(context).popUntil((r) => r.isFirst);
  tabIndex.value = 0;
  mapFocus.value = null;
  mapFocus.value = s;
}

const accent = Color(0xFF3BE37F);

class StationLogo extends StatelessWidget {
  const StationLogo(this.station, {super.key, this.size = 46});
  final Station station;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(station.flag, style: TextStyle(fontSize: size * 0.45)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: !station.hasLogo
          ? fallback
          : Image.network(
              station.favicon,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (_, child, p) => p == null ? child : fallback,
            ),
    );
  }
}

/// Barre animate "in onda".
class LiveBars extends StatefulWidget {
  const LiveBars({super.key, this.color = accent});
  final Color color;
  @override
  State<LiveBars> createState() => _LiveBarsState();
}

class _LiveBarsState extends State<LiveBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        double h(double phase) => 6 + 12 * (0.5 + 0.5 * (1 - ((t + phase) % 1 * 2 - 1).abs()));
        return SizedBox(
          width: 20,
          height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final ph in [0.0, 0.35, 0.7])
                Container(width: 4, height: h(ph), color: widget.color),
            ],
          ),
        );
      },
    );
  }
}

class StationTile extends StatelessWidget {
  const StationTile(this.station, {super.key, this.showPlace = true});
  final Station station;
  final bool showPlace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([RadioPlayer.i, Library.i, RecController.i]),
      builder: (context, _) {
        final p = RadioPlayer.i;
        final active = p.isCurrent(station);
        final fav = Library.i.isFavorite(station);
        final sub = [
          if (showPlace) '${station.flag} ${station.place}',
          if (station.quality.isNotEmpty) station.quality,
          if (!showPlace && station.tagList.isNotEmpty) station.tagList.join(', '),
        ].join(' · ');
        return ListTile(
          leading: StationLogo(station),
          title: Text(station.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: active ? accent : null)),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active && p.isBuffering)
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (active && p.isPlaying)
                const LiveBars(),
              _TileRec(station),
              IconButton(
                tooltip: fav ? 'Togli dai preferiti' : 'Aggiungi ai preferiti',
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                    color: fav ? Colors.pinkAccent : null),
                onPressed: () => Library.i.toggleFavorite(station),
              ),
            ],
          ),
          onTap: () => active && p.isPlaying ? openPlayer(context) : p.play(station),
        );
      },
    );
  }
}

/// Elenco di stazioni in un foglio che sale dal basso.
Future<void> showStationsSheet(BuildContext context,
    {required String title,
    required String subtitle,
    required List<Station> stations,
    void Function(BuildContext)? action,
    String actionLabel = ''}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: stations.length > 4 ? 0.55 : 0.4,
      minChildSize: 0.25,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          ListTile(
            title: Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            subtitle: Text(subtitle),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.flag),
                  label: Text(actionLabel),
                  onPressed: () => action(context),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: stations.length,
              itemBuilder: (_, i) => StationTile(stations[i], showPlace: false),
            ),
          ),
        ],
      ),
    ),
  );
}

void openPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const PlayerSheet(),
  );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([RadioPlayer.i, RecController.i]),
      builder: (context, _) {
        final p = RadioPlayer.i;
        final s = p.current;
        if (s == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surfaceContainerHigh,
          child: InkWell(
            onTap: () => openPlayer(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  StationLogo(s, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${s.flag}  ${s.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          p.isBuffering
                              ? 'Collegamento…'
                              : (p.isPlaying ? (p.nowPlaying ?? s.place) : 'In pausa'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (p.isPlaying && !p.isBuffering) const LiveBars(),
                  const RecButton(),
                  IconButton(
                    iconSize: 34,
                    icon: p.isBuffering
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(p.isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
                            color: accent),
                    onPressed: p.toggle,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([RadioPlayer.i, Library.i, RecController.i]),
      builder: (context, _) {
        final p = RadioPlayer.i;
        final s = p.current;
        if (s == null) return const SizedBox(height: 120);
        final scheme = Theme.of(context).colorScheme;
        final fav = Library.i.isFavorite(s);
        final sleep = p.sleepAt;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StationLogo(s, size: 150),
              const SizedBox(height: 18),
              Text(s.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${s.flag}  ${s.place}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (s.quality.isNotEmpty || s.tagList.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text([s.quality, s.tagList.join(', ')].where((x) => x.isNotEmpty).join(' · '),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    if (p.isPlaying && !p.isBuffering)
                      const LiveBars()
                    else
                      Icon(Icons.radio, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.isBuffering
                            ? 'Collegamento alla radio…'
                            : !p.isPlaying
                                ? 'Fermo'
                                : (p.nowPlaying ?? 'In diretta'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 30,
                    tooltip: 'Preferito',
                    icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                        color: fav ? Colors.pinkAccent : null),
                    onPressed: () => Library.i.toggleFavorite(s),
                  ),
                  IconButton.filled(
                    iconSize: 44,
                    style: IconButton.styleFrom(
                        backgroundColor: accent, foregroundColor: Colors.black),
                    icon: p.isBuffering
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: Colors.black),
                            ))
                        : Icon(p.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
                    onPressed: p.toggle,
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Spegnimento automatico',
                    icon: Icon(Icons.bedtime_outlined,
                        size: 30, color: sleep != null ? accent : null),
                    onSelected: (m) => p.setSleep(m == 0 ? null : Duration(minutes: m)),
                    itemBuilder: (_) => [
                      for (final m in [15, 30, 45, 60, 90, 120])
                        PopupMenuItem(value: m, child: Text('Spegni tra $m minuti')),
                      if (sleep != null)
                        const PopupMenuItem(value: 0, child: Text('Annulla spegnimento')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const BigRecButton(),
              if (sleep != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Si spegne alle ${sleep.hour.toString().padLeft(2, '0')}:${sleep.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: accent),
                  ),
                ),
              if (s.hasGeo) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.public),
                  label: const Text('Mostra sulla mappa'),
                  onPressed: () => showOnMap(context, s),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}


const recRed = Color(0xFFFF4D4D);

/// Pulsante rotondo ● nel mini player: avvia / ferma la registrazione.
class RecButton extends StatelessWidget {
  const RecButton({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = RecController.i;
    final p = RadioPlayer.i;
    if (rec.saving != null) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: recRed)),
      );
    }
    return IconButton(
      tooltip: rec.recording ? 'Ferma e salva' : 'Registra',
      iconSize: 30,
      icon: Icon(rec.recording ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
          color: recRed),
      onPressed: rec.recording
          ? rec.stopAndSave
          : (p.isPlaying && !p.isBuffering ? rec.start : null),
    );
  }
}

/// Pulsante grande nel lettore.
class BigRecButton extends StatelessWidget {
  const BigRecButton({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = RecController.i;
    final p = RadioPlayer.i;
    if (rec.saving != null) return const RecBanner();
    if (rec.recording) return const RecBanner();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: recRed,
          side: const BorderSide(color: recRed),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text('Registra questa radio', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: p.isPlaying && !p.isBuffering ? rec.start : null,
      ),
    );
  }
}

/// Striscia rossa: REC, tempo, dimensione, Ferma.
class RecBanner extends StatefulWidget {
  const RecBanner({super.key});
  @override
  State<RecBanner> createState() => _RecBannerState();
}

class _RecBannerState extends State<RecBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RecController.i,
      builder: (context, _) {
        final rec = RecController.i;
        if (!rec.busy) return const SizedBox.shrink();
        final saving = rec.saving;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: recRed.withValues(alpha: 0.16),
            border: Border.all(color: recRed.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: saving != null
              ? Row(
                  children: [
                    const Icon(Icons.save_alt, color: recRed),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(saving > 0 ? 'Salvataggio… ${(saving * 100).round()}%' : 'Salvataggio…',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: saving > 0 ? saving : null, color: recRed),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : Row(
                  children: [
                    FadeTransition(
                      opacity: _blink,
                      child: const Icon(Icons.fiber_manual_record, color: recRed, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text('REC ${fmtDur(rec.elapsed)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${fmtSize(rec.bytes)} · ${rec.station?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: recRed),
                      icon: const Icon(Icons.stop),
                      label: const Text('Ferma e salva'),
                      onPressed: rec.stopAndSave,
                    ),
                  ],
                ),
        );
      },
    );
  }
}


/// ● accanto al ❤️: grigio = radio spenta, rosso = pronto, ■ = sta registrando.
class _TileRec extends StatelessWidget {
  const _TileRec(this.station);
  final Station station;

  @override
  Widget build(BuildContext context) {
    final rec = RecController.i;
    final p = RadioPlayer.i;
    if (rec.isRecording(station)) {
      if (rec.saving != null) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: recRed)),
        );
      }
      return IconButton(
        tooltip: 'Ferma e salva',
        icon: const Icon(Icons.stop_circle, color: recRed),
        onPressed: rec.stopAndSave,
      );
    }
    if (rec.isPending(station)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: recRed)),
      );
    }
    final ready = p.isCurrent(station) && p.isPlaying;
    return IconButton(
      tooltip: 'Registra',
      icon: Icon(Icons.fiber_manual_record,
          color: ready ? recRed : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      onPressed: rec.busy ? null : () => rec.recordStation(station),
    );
  }
}
