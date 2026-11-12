// Traduzione scritta online (Google Translate): più precisa di quella offline
// e non aggiunge peso all'app. Serve internet solo mentre traduce.

import 'dart:convert';

import 'package:http/http.dart' as http;

class OnlineTranslator {
  static const _url = 'https://translate.googleapis.com/translate_a/single';

  /// Traduce un testo. Restituisce (traduzione, lingua riconosciuta).
  static Future<(String, String?)> _one(String text, String from, String to) async {
    final res = await http
        .post(
          Uri.parse('$_url?client=gtx&sl=$from&tl=$to&dt=t&ie=UTF-8&oe=UTF-8'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
          body: 'q=${Uri.encodeQueryComponent(text)}',
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('traduzione: errore ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    final b = StringBuffer();
    for (final part in (data[0] as List? ?? const [])) {
      if (part is List && part.isNotEmpty && part[0] is String) b.write(part[0]);
    }
    final detected = data.length > 2 && data[2] is String ? data[2] as String : null;
    return (b.toString(), detected);
  }

  /// Lingua del testo (es. "es"), o null.
  static Future<String?> detect(String text) async {
    try {
      final (_, d) = await _one(text, 'auto', 'en');
      return d?.split('-').first;
    } catch (_) {
      return null;
    }
  }

  /// Traduce ogni frase. Le frasi vanno a gruppi (meno richieste),
  /// e se un gruppo non torna diviso bene le traduce una per una.
  static Future<List<String>> lines(List<String> src, String from, String to,
      {void Function(int done)? progress}) async {
    final out = <String>[];
    var i = 0;
    while (i < src.length) {
      var j = i, len = 0;
      while (j < src.length && (j == i || len + src[j].length < 3500) && j - i < 40) {
        len += src[j].length + 1;
        j++;
      }
      final group = src.sublist(i, j).map((s) => s.replaceAll('\n', ' ')).toList();
      List<String>? got;
      try {
        final (t, _) = await _one(group.join('\n'), from, to);
        final parts = t.split('\n').map((s) => s.trim()).toList();
        if (parts.length == group.length) got = parts;
      } catch (_) {}
      if (got == null) {
        got = [];
        for (final s in group) {
          got.add((await _one(s, from, to)).$1.trim());
        }
      }
      out.addAll(got);
      i = j;
      progress?.call(out.length);
    }
    return out;
  }
}
