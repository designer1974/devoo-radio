import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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

/// Pagina Pro come Devoo POS: prova gratuita di 7 giorni, codice dispositivo, chiave di licenza.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.reason});
  final String? reason;
  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _benefits = [
    (Icons.all_inclusive, 'Registrazione illimitata, anche di ore'),
    (Icons.alarm_on, 'Registrazioni programmate: partono da sole anche ad app chiusa'),
    (Icons.repeat, '«Ogni giorno» per il tuo programma fisso'),
    (Icons.content_cut, 'Editor: taglia e unisci'),
    (Icons.high_quality, 'Tutte le qualità audio, da 10 a 56 MB l\'ora'),
    (Icons.block, 'Nessuna pubblicità'),
  ];

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)));
  }

  Future<void> _trial() async {
    if (await Pro.i.startTrial()) {
      if (!mounted) return;
      _snack('Prova Pro attiva per 7 giorni. Buon ascolto!');
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await Pro.i.activate(_key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _snack('Devoo Radio Pro attivato. Grazie!');
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _key.text = d!.text!.trim());
  }

  void _request(String plan) {
    final e = Pro.i.license?.expires;
    String two(int n) => n.toString().padLeft(2, '0');
    final msg = 'Vorrei Devoo Radio Pro ($plan).\n'
        'Codice dispositivo: ${Pro.i.deviceCode}\n'
        'Telefono: ${Pro.i.model}'
        // nei rinnovi la nuova licenza parte dalla scadenza attuale: non si perdono giorni
        '${e == null ? '' : '\nScadenza attuale: ${e.year}-${two(e.month)}-${two(e.day)}'}';
    Share.share(msg, subject: 'Devoo Radio Pro');
  }

  Widget _price(String title, String price, String note, ColorScheme scheme) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(children: [
            Text(title, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            Text(price, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            Text(note, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Devoo Radio Pro')),
      body: ListenableBuilder(
        listenable: Pro.i,
        builder: (context, _) {
          final p = Pro.i;
          final active = p.isPro;
          final statusColor = active ? accent : (p.expired || p.inGrace ? Colors.orangeAccent : scheme.onSurfaceVariant);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              const Icon(Icons.workspace_premium, size: 52, color: accent),
              const SizedBox(height: 6),
              Text(
                widget.reason ?? 'Registra senza limiti, programma i tuoi programmi preferiti, niente pubblicità.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
              ),
              const SizedBox(height: 12),
              // stato attuale
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  Icon(active ? Icons.verified : Icons.info_outline, color: statusColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.statusText, style: TextStyle(fontWeight: FontWeight.w700, color: statusColor))),
                ]),
              ),
              const SizedBox(height: 10),
              for (final (icon, text) in _benefits)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: accent),
                  title: Text(text, style: const TextStyle(fontSize: 15)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                _price('Mensile', Pro.priceMonth, '31 giorni', scheme),
                const SizedBox(width: 10),
                _price('Annuale', Pro.priceYear, '365 giorni · risparmi il 66%', scheme),
              ]),
              const SizedBox(height: 16),
              if (!p.isPro && !p.trialUsed && !p.isProPackage) ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _trial,
                  child: const Text('Prova gratis 7 giorni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 6),
                Text('Senza carta e senza abbonamento: dopo 7 giorni torna gratis da sola.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 18),
              ],
              if (!p.isProPackage) ...[
                const Text('1. Chiedi la licenza', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Codice dispositivo', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        SelectableText(p.deviceCode,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
                      ]),
                    ),
                    IconButton(
                      tooltip: tr('Copia'),
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: p.deviceCode));
                        _snack('Codice copiato');
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text('Mensile ${Pro.priceMonth}'),
                      onPressed: () => _request('mensile ${Pro.priceMonth}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text('Annuale ${Pro.priceYear}'),
                      onPressed: () => _request('annuale ${Pro.priceYear}'),
                    ),
                  ),
                ]),
                Text('Si apre WhatsApp (o SMS, email) con il codice già scritto.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 18),
                const Text('2. Inserisci la chiave che ricevi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                TextField(
                  controller: _key,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: tr('Incolla qui la chiave'),
                    errorText: _error == null ? null : tr(_error!),
                    suffixIcon: IconButton(tooltip: tr('Incolla'), icon: const Icon(Icons.content_paste), onPressed: _paste),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _busy ? null : _activate,
                  child: Text(_busy ? '…' : 'Attiva', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                '${p.appName} · versione ${appBuild > 0 ? 'build $appBuild' : 'sviluppo'}\n'
                'Termini: ${Pro.termsUrl} · Privacy: ${Pro.privacyUrl}\n'
                'Sviluppata da ${Pro.developer} · ${Pro.website}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
