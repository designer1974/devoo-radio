import 'package:flutter/material.dart' hide Text;

import 'pro.dart';
import 'widgets.dart';
import 'i18n.dart';

/// Apre «Passa a Pro». [reason] = cosa voleva fare l'utente (mostrato in alto).
Future<void> openPaywall(BuildContext context, {String? reason}) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaywallPage(reason: reason)));
}

/// Controlla Pro: se manca apre la pagina e ritorna false.
Future<bool> requirePro(BuildContext context, String reason) async {
  if (Pro.i.isPro) return true;
  await openPaywall(context, reason: reason);
  return Pro.i.isPro;
}

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.reason});
  final String? reason;
  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  bool _yearly = true;

  static const _benefits = [
    (Icons.all_inclusive, 'Registrazione illimitata, anche di ore'),
    (Icons.alarm_on, 'Registrazioni programmate: partono da sole anche ad app chiusa'),
    (Icons.repeat, '«Ogni giorno» per il tuo programma fisso'),
    (Icons.content_cut, 'Editor: taglia e unisci'),
    (Icons.high_quality, 'Tutte le qualità audio, da 10 a 56 MB l\'ora'),
    (Icons.block, 'Nessuna pubblicità'),
  ];

  void _buy() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('L\'abbonamento si attiva con l\'uscita su AppGallery e Galaxy Store. Grazie!'),
    ));
  }

  Widget _plan({required bool yearly, required String title, required String price, required String note}) {
    final sel = _yearly == yearly;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: sel ? accent.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: sel ? accent : scheme.outlineVariant, width: sel ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _yearly = yearly),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? accent : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(note, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ]),
              ),
              Text(price, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Icon(Icons.workspace_premium, size: 56, color: accent),
          const SizedBox(height: 8),
          const Text('Devoo Radio Pro',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            widget.reason ?? 'Registra senza limiti, programma i tuoi programmi preferiti, niente pubblicità.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          for (final (icon, text) in _benefits)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: accent),
              title: Text(text, style: const TextStyle(fontSize: 15)),
            ),
          const SizedBox(height: 14),
          _plan(yearly: true, title: 'Annuale · risparmi il 66%', price: '3,99 €', note: '0,33 € al mese · 7 giorni gratis'),
          const SizedBox(height: 10),
          _plan(yearly: false, title: 'Mensile', price: '0,99 €', note: 'disdici quando vuoi'),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _buy,
            child: Text(_yearly ? 'Prova gratis 7 giorni' : 'Abbonati a 0,99 € al mese',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          Text(
            _yearly ? 'Poi 3,99 € l\'anno. Disdici quando vuoi dallo store.' : 'Si rinnova ogni mese. Disdici quando vuoi dallo store.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text(
            'Ripristina acquisto · Termini: ${Pro.termsUrl} · Privacy: ${Pro.privacyUrl}\n'
            'Sviluppata da ${Pro.developer} · ${Pro.website}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
