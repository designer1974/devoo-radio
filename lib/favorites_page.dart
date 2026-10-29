import 'package:flutter/material.dart';

import 'store.dart';
import 'widgets.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Library.i,
        builder: (context, _) {
          final lib = Library.i;
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Preferiti',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
              ),
              if (lib.favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Tocca il ♡ accanto a una radio per salvarla qui.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              else
                for (final s in lib.favorites) StationTile(s),
              if (lib.recents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 4, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Ascoltate di recente',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      TextButton(onPressed: lib.clearRecents, child: const Text('Cancella')),
                    ],
                  ),
                ),
                for (final s in lib.recents) StationTile(s),
              ],
            ],
          );
        },
      ),
    );
  }
}
