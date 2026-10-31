import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:shared_preferences/shared_preferences.dart';

/// Lingue dell'app. L'italiano è la lingua del codice: le altre si traducono da qui.
class Lang extends ChangeNotifier {
  Lang._();
  static final i = Lang._();

  static const all = [
    ('it', '🇮🇹', 'Italiano'),
    ('en', '🇬🇧', 'English'),
    ('fr', '🇫🇷', 'Français'),
    ('es', '🇪🇸', 'Español'),
    ('de', '🇩🇪', 'Deutsch'),
    ('ar', '🇲🇦', 'العربية'),
  ];
  static const codes = ['it', 'en', 'fr', 'es', 'de', 'ar'];

  String code = 'it';

  String get flag => all.firstWhere((l) => l.$1 == code).$2;
  String get name => all.firstWhere((l) => l.$1 == code).$3;

  Future<void> init() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString('lang');
    } catch (_) {}
    if (saved != null && codes.contains(saved)) {
      code = saved;
    } else {
      // prima volta: la lingua del telefono, altrimenti inglese
      final dev = ui.PlatformDispatcher.instance.locale.languageCode;
      code = codes.contains(dev) ? dev : 'en';
    }
  }

  Future<void> set(String c) async {
    if (!codes.contains(c) || c == code) return;
    code = c;
    _cache.clear();
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString('lang', c);
    } catch (_) {}
  }
}

final _cache = <String, String>{};
List<(RegExp, String, List<String>)>? _patterns;

int _idx(String code) => switch (code) { 'en' => 0, 'fr' => 1, 'es' => 2, 'de' => 3, 'ar' => 4, _ => -1 };

/// Traduce un testo italiano nella lingua scelta. Testi con parti variabili: chiavi con {}.
String tr(String s, [String? code]) {
  final c = code ?? Lang.i.code;
  final ix = _idx(c);
  if (ix < 0 || s.isEmpty) return s;
  final key = '$c|$s';
  final hit = _cache[key];
  if (hit != null) return hit;
  String out = s;
  final exact = _dict[s];
  if (exact != null) {
    out = exact[ix];
  } else {
    _patterns ??= [
      for (final e in _dict.entries.where((e) => e.key.contains('{}')).toList()
        ..sort((a, b) => b.key.replaceAll('{}', '').length.compareTo(a.key.replaceAll('{}', '').length)))
        (
          RegExp('^${e.key.split('{}').map(RegExp.escape).join('(.*?)')}\$', dotAll: true),
          e.key,
          e.value,
        ),
    ];
    for (final (re, _, vals) in _patterns!) {
      final mm = re.firstMatch(s);
      if (mm == null) continue;
      final parts = vals[ix].split('{}');
      final b = StringBuffer(parts.first);
      for (var g = 1; g < parts.length; g++) {
        final cap = g <= mm.groupCount ? (mm.group(g) ?? '') : '';
        b.write(_dict.containsKey(cap) ? _dict[cap]![ix] : cap);
        b.write(parts[g]);
      }
      out = b.toString();
      break;
    }
  }
  if (_cache.length > 3000) _cache.clear();
  _cache[key] = out;
  return out;
}

/// Giorni della settimana (1 = lunedì).
String weekdayName(int weekday) {
  const names = {
    'it': ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'],
    'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    'fr': ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'],
    'es': ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'],
    'de': ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
    'ar': ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
  };
  final l = names[Lang.i.code] ?? names['it']!;
  return l[(weekday - 1) % 7];
}

/// Al posto di Text di Flutter: traduce da solo e si aggiorna quando cambia la lingua.
class Text extends m.StatelessWidget {
  const Text(this.data, {super.key, this.style, this.maxLines, this.overflow, this.textAlign, this.softWrap});
  final String data;
  final m.TextStyle? style;
  final int? maxLines;
  final m.TextOverflow? overflow;
  final m.TextAlign? textAlign;
  final bool? softWrap;

  @override
  m.Widget build(m.BuildContext context) {
    final code = m.Localizations.maybeLocaleOf(context)?.languageCode ?? Lang.i.code;
    return m.Text(tr(data, code),
        style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign, softWrap: softWrap);
  }
}

/// Italiano → [inglese, francese, spagnolo, tedesco, arabo]
const Map<String, List<String>> _dict = {
  'Radio nazionali e web': ['National and web stations', 'Radios nationales et web', 'Radios nacionales y web', 'Landesweite und Web-Sender', 'إذاعات وطنية وعلى الإنترنت'],
  'Altre radio': ['Other stations', 'Autres radios', 'Otras radios', 'Weitere Sender', 'إذاعات أخرى'],
  'Tutte le radio': ['All stations', 'Toutes les radios', 'Todas las radios', 'Alle Sender', 'كل الإذاعات'],
  'Cerca città o radio': ['Search city or station', 'Chercher une ville ou une radio', 'Buscar ciudad o radio', 'Stadt oder Sender suchen', 'ابحث عن مدينة أو إذاعة'],
  'Nessun risultato': ['No results', 'Aucun résultat', 'Sin resultados', 'Keine Ergebnisse', 'لا نتائج'],
  'Globo': ['Globe', 'Globe', 'Globo', 'Globus', 'الكرة الأرضية'],
  'Rapporto errori': ['Error report', "Rapport d'erreurs", 'Informe de errores', 'Fehlerbericht', 'تقرير الأخطاء'],
  'Copia': ['Copy', 'Copier', 'Copiar', 'Kopieren', 'نسخ'],
  'Chiudi': ['Close', 'Fermer', 'Cerrar', 'Schließen', 'إغلاق'],
  // navigazione
  'Mappa': ['Map', 'Carte', 'Mapa', 'Karte', 'الخريطة'],
  'Cerca': ['Search', 'Rechercher', 'Buscar', 'Suchen', 'بحث'],
  'Preferiti': ['Favourites', 'Favoris', 'Favoritos', 'Favoriten', 'المفضلة'],
  'Registrate': ['Recordings', 'Enregistrements', 'Grabaciones', 'Aufnahmen', 'التسجيلات'],
  'Lingua': ['Language', 'Langue', 'Idioma', 'Sprache', 'اللغة'],
  // mappa
  'Tocca un puntino verde': ['Tap a green dot', 'Touchez un point vert', 'Toca un punto verde', 'Tippe auf einen grünen Punkt', 'اضغط على نقطة خضراء'],
  'Scarico le radio del mondo… {}%': ['Downloading the world\'s radios… {}%', 'Téléchargement des radios du monde… {}%', 'Descargando las radios del mundo… {}%', 'Radios der Welt werden geladen… {}%', 'جارٍ تحميل إذاعات العالم… {}%'],
  '{} radio · {} città · scarico…': ['{} stations · {} cities · downloading…', '{} radios · {} villes · téléchargement…', '{} radios · {} ciudades · descargando…', '{} Sender · {} Städte · lädt…', '{} إذاعة · {} مدينة · جارٍ التحميل…'],
  '{} radio · {} città': ['{} stations · {} cities', '{} radios · {} villes', '{} radios · {} ciudades', '{} Sender · {} Städte', '{} إذاعة · {} مدينة'],
  'Sorprendimi': ['Surprise me', 'Surprends-moi', 'Sorpréndeme', 'Überrasch mich', 'فاجئني'],
  'Dove sono': ['Where am I', 'Où suis-je', 'Dónde estoy', 'Wo bin ich', 'أين أنا'],
  'Radio vicino a te': ['Radio near you', 'Radios près de toi', 'Radios cerca de ti', 'Radios in deiner Nähe', 'إذاعات قريبة منك'],
  'Sei a {}': ['You are in {}', 'Tu es à {}', 'Estás en {}', 'Du bist in {}', 'أنت في {}'],
  'Posizione non trovata. Controlla internet e riprova.': ['Location not found. Check your internet and try again.', 'Position introuvable. Vérifie Internet et réessaie.', 'Ubicación no encontrada. Revisa internet e inténtalo de nuevo.', 'Standort nicht gefunden. Prüfe das Internet und versuche es erneut.', 'تعذّر تحديد الموقع. تحقّق من الإنترنت وحاول مجددًا.'],
  'Cerco dove sei…': ['Finding where you are…', 'Je cherche où tu es…', 'Buscando dónde estás…', 'Suche deinen Standort…', 'جارٍ تحديد موقعك…'],
  'Aggiorna le radio': ['Refresh stations', 'Actualiser les radios', 'Actualizar radios', 'Sender aktualisieren', 'تحديث الإذاعات'],
  'Cambia mappa': ['Change map', 'Changer de carte', 'Cambiar mapa', 'Karte wechseln', 'تغيير الخريطة'],
  'Passa a Pro': ['Go Pro', 'Passer à Pro', 'Pásate a Pro', 'Zu Pro wechseln', 'الترقية إلى Pro'],
  '1 radio qui': ['1 station here', '1 radio ici', '1 radio aquí', '1 Sender hier', 'إذاعة واحدة هنا'],
  '{} radio qui': ['{} stations here', '{} radios ici', '{} radios aquí', '{} Sender hier', '{} إذاعة هنا'],
  'Tutte le radio di {}': ['All stations in {}', 'Toutes les radios : {}', 'Todas las radios de {}', 'Alle Sender: {}', 'كل إذاعات {}'],
  'Riprova': ['Try again', 'Réessayer', 'Reintentar', 'Erneut versuchen', 'أعد المحاولة'],
  'Nessuna connessione. Controlla internet e riprova.': ['No connection. Check your internet and try again.', 'Pas de connexion. Vérifie Internet et réessaie.', 'Sin conexión. Revisa internet e inténtalo de nuevo.', 'Keine Verbindung. Prüfe das Internet und versuche es erneut.', 'لا يوجد اتصال. تحقّق من الإنترنت وحاول مجددًا.'],
  'Frecce: muovi · OK: apri la città · CH+ / CH−: zoom · Indietro: menu': ['Arrows: move · OK: open city · CH+ / CH−: zoom · Back: menu', 'Flèches : bouger · OK : ouvrir la ville · CH+ / CH− : zoom · Retour : menu', 'Flechas: mover · OK: abrir ciudad · CH+ / CH−: zoom · Atrás: menú', 'Pfeile: bewegen · OK: Stadt öffnen · CH+ / CH−: Zoom · Zurück: Menü', 'الأسهم: تحريك · OK: فتح المدينة · CH+ / CH−: تكبير · رجوع: القائمة'],
  'Premi su per tornare alla mappa': ['Press up to go back to the map', 'Appuie sur haut pour revenir à la carte', 'Pulsa arriba para volver al mapa', 'Drücke hoch, um zur Karte zurückzukehren', 'اضغط للأعلى للعودة إلى الخريطة'],
  'Mondo': ['World', 'Monde', 'Mundo', 'Welt', 'العالم'],
  // lettore
  'Collegamento…': ['Connecting…', 'Connexion…', 'Conectando…', 'Verbinde…', 'جارٍ الاتصال…'],
  'Collegamento alla radio…': ['Connecting to the station…', 'Connexion à la radio…', 'Conectando con la radio…', 'Verbinde mit dem Sender…', 'جارٍ الاتصال بالإذاعة…'],
  'In pausa': ['Paused', 'En pause', 'En pausa', 'Pausiert', 'متوقف مؤقتًا'],
  'Fermo': ['Stopped', 'Arrêté', 'Detenido', 'Gestoppt', 'متوقف'],
  'In diretta': ['Live', 'En direct', 'En directo', 'Live', 'مباشر'],
  'Preferito': ['Favourite', 'Favori', 'Favorito', 'Favorit', 'مفضّل'],
  'Aggiungi ai preferiti': ['Add to favourites', 'Ajouter aux favoris', 'Añadir a favoritos', 'Zu Favoriten', 'أضف إلى المفضلة'],
  'Togli dai preferiti': ['Remove from favourites', 'Retirer des favoris', 'Quitar de favoritos', 'Aus Favoriten entfernen', 'إزالة من المفضلة'],
  'Spegnimento automatico': ['Sleep timer', 'Minuterie de veille', 'Temporizador', 'Schlaftimer', 'مؤقت الإيقاف'],
  'Spegni tra {} minuti': ['Stop in {} minutes', 'Arrêter dans {} minutes', 'Apagar en {} minutos', 'In {} Minuten stoppen', 'إيقاف بعد {} دقيقة'],
  'Annulla spegnimento': ['Cancel sleep timer', 'Annuler la minuterie', 'Cancelar temporizador', 'Timer abbrechen', 'إلغاء المؤقت'],
  'Si spegne alle {}': ['Stops at {}', 'S\'arrête à {}', 'Se apaga a las {}', 'Stoppt um {}', 'يتوقف عند {}'],
  'Mostra sulla mappa': ['Show on map', 'Voir sur la carte', 'Ver en el mapa', 'Auf der Karte zeigen', 'عرض على الخريطة'],
  'Programma': ['Schedule', 'Programmer', 'Programar', 'Planen', 'جدولة'],
  'Programma registrazione': ['Schedule recording', 'Programmer un enregistrement', 'Programar grabación', 'Aufnahme planen', 'جدولة تسجيل'],
  'Altro': ['More', 'Plus', 'Más', 'Mehr', 'المزيد'],
  '«{}» non risponde. Prova un\'altra radio.': ['"{}" is not responding. Try another station.', '« {} » ne répond pas. Essaie une autre radio.', '«{}» no responde. Prueba otra radio.', '„{}" antwortet nicht. Probiere einen anderen Sender.', '«{}» لا تستجيب. جرّب إذاعة أخرى.'],
  // registrazione
  'Registra': ['Record', 'Enregistrer', 'Grabar', 'Aufnehmen', 'تسجيل'],
  'Registra questa radio': ['Record this station', 'Enregistrer cette radio', 'Grabar esta radio', 'Diesen Sender aufnehmen', 'سجّل هذه الإذاعة'],
  'Ferma e salva': ['Stop and save', 'Arrêter et enregistrer', 'Detener y guardar', 'Stoppen und speichern', 'إيقاف وحفظ'],
  'Avvio registrazione…': ['Starting recording…', 'Démarrage de l\'enregistrement…', 'Iniciando grabación…', 'Aufnahme startet…', 'جارٍ بدء التسجيل…'],
  'Salvataggio…': ['Saving…', 'Enregistrement…', 'Guardando…', 'Speichern…', 'جارٍ الحفظ…'],
  'Salvataggio {}%': ['Saving {}%', 'Enregistrement {}%', 'Guardando {}%', 'Speichern {}%', 'جارٍ الحفظ {}%'],
  '● REC {} · {}': ['● REC {} · {}', '● REC {} · {}', '● REC {} · {}', '● REC {} · {}', '● REC {} · {}'],
  '{} · fino alle {} · {}': ['{} · until {} · {}', '{} · jusqu\'à {} · {}', '{} · hasta las {} · {}', '{} · bis {} · {}', '{} · حتى {} · {}'],
  'Impossibile registrare questa radio': ['This station can\'t be recorded', 'Impossible d\'enregistrer cette radio', 'No se puede grabar esta radio', 'Dieser Sender kann nicht aufgenommen werden', 'لا يمكن تسجيل هذه الإذاعة'],
  'C\'è già una registrazione programmata in corso': ['A scheduled recording is already running', 'Un enregistrement programmé est déjà en cours', 'Ya hay una grabación programada en curso', 'Eine geplante Aufnahme läuft bereits', 'هناك تسجيل مجدول قيد التشغيل بالفعل'],
  'Salvata in Registrate · {}': ['Saved in Recordings · {}', 'Enregistré dans Enregistrements · {}', 'Guardada en Grabaciones · {}', 'In Aufnahmen gespeichert · {}', 'حُفظ في التسجيلات · {}'],
  'Registrazione troppo corta, non salvata': ['Recording too short, not saved', 'Enregistrement trop court, non sauvegardé', 'Grabación demasiado corta, no guardada', 'Aufnahme zu kurz, nicht gespeichert', 'التسجيل قصير جدًا، لم يُحفظ'],
  'Registrazione non salvata': ['Recording not saved', 'Enregistrement non sauvegardé', 'Grabación no guardada', 'Aufnahme nicht gespeichert', 'لم يُحفظ التسجيل'],
  'Registrazione programmata salvata in Registrate': ['Scheduled recording saved in Recordings', 'Enregistrement programmé sauvegardé', 'Grabación programada guardada en Grabaciones', 'Geplante Aufnahme in Aufnahmen gespeichert', 'حُفظ التسجيل المجدول في التسجيلات'],
  'Registrazione interrotta recuperata ✔': ['Interrupted recording recovered ✔', 'Enregistrement interrompu récupéré ✔', 'Grabación interrumpida recuperada ✔', 'Unterbrochene Aufnahme wiederhergestellt ✔', 'تم استرجاع التسجيل المتوقف ✔'],
  '{} registrazioni interrotte recuperate ✔': ['{} interrupted recordings recovered ✔', '{} enregistrements interrompus récupérés ✔', '{} grabaciones interrumpidas recuperadas ✔', '{} unterbrochene Aufnahmen wiederhergestellt ✔', 'تم استرجاع {} تسجيلات متوقفة ✔'],
  'Registrazione salvata (10 minuti). Con Pro registri senza limiti.': ['Recording saved (10 minutes). With Pro you record without limits.', 'Enregistrement sauvegardé (10 minutes). Avec Pro, enregistre sans limite.', 'Grabación guardada (10 minutos). Con Pro grabas sin límites.', 'Aufnahme gespeichert (10 Minuten). Mit Pro ohne Limit aufnehmen.', 'حُفظ التسجيل (10 دقائق). مع Pro سجّل بلا حدود.'],
  // qualità
  'Voce  ★ consigliata': ['Voice  ★ recommended', 'Voix  ★ conseillée', 'Voz  ★ recomendada', 'Sprache  ★ empfohlen', 'صوت  ★ موصى به'],
  'Minima': ['Minimum', 'Minimale', 'Mínima', 'Minimal', 'أدنى'],
  'Media': ['Medium', 'Moyenne', 'Media', 'Mittel', 'متوسطة'],
  'Alta': ['High', 'Haute', 'Alta', 'Hoch', 'عالية'],
  '32 kbps stereo · ~14 MB all\'ora · parlato e musica': ['32 kbps stereo · ~14 MB per hour · speech and music', '32 kbps stéréo · ~14 Mo par heure · voix et musique', '32 kbps estéreo · ~14 MB por hora · voz y música', '32 kbps Stereo · ~14 MB pro Stunde · Sprache und Musik', '32 kbps ستيريو · ~14 MB في الساعة · كلام وموسيقى'],
  '24 kbps mono · ~10 MB all\'ora · solo parlato': ['24 kbps mono · ~10 MB per hour · speech only', '24 kbps mono · ~10 Mo par heure · voix seule', '24 kbps mono · ~10 MB por hora · solo voz', '24 kbps Mono · ~10 MB pro Stunde · nur Sprache', '24 kbps أحادي · ~10 MB في الساعة · كلام فقط'],
  '64 kbps · ~28 MB all\'ora · musica': ['64 kbps · ~28 MB per hour · music', '64 kbps · ~28 Mo par heure · musique', '64 kbps · ~28 MB por hora · música', '64 kbps · ~28 MB pro Stunde · Musik', '64 kbps · ~28 MB في الساعة · موسيقى'],
  '128 kbps · ~56 MB all\'ora · musica alta fedeltà': ['128 kbps · ~56 MB per hour · hi-fi music', '128 kbps · ~56 Mo par heure · musique haute fidélité', '128 kbps · ~56 MB por hora · música alta fidelidad', '128 kbps · ~56 MB pro Stunde · HiFi-Musik', '128 kbps · ~56 MB في الساعة · موسيقى عالية الدقة'],
  'Qualità e spazio': ['Quality and storage', 'Qualité et espace', 'Calidad y espacio', 'Qualität und Speicher', 'الجودة والمساحة'],
  'Qualità': ['Quality', 'Qualité', 'Calidad', 'Qualität', 'الجودة'],
  'Formato M4A (AAC): si apre su WhatsApp, email, Android e iPhone. La radio viene registrata direttamente dallo stream, senza perdite e senza rumori.': ['M4A (AAC) format: opens on WhatsApp, email, Android and iPhone. The station is recorded straight from the stream, lossless and noise-free.', 'Format M4A (AAC) : s\'ouvre sur WhatsApp, e-mail, Android et iPhone. La radio est enregistrée directement depuis le flux, sans perte ni bruit.', 'Formato M4A (AAC): se abre en WhatsApp, correo, Android y iPhone. La radio se graba directamente del stream, sin pérdidas ni ruido.', 'M4A-Format (AAC): öffnet sich in WhatsApp, E-Mail, Android und iPhone. Der Sender wird direkt aus dem Stream aufgenommen, verlustfrei und rauschfrei.', 'صيغة M4A (AAC): تفتح على واتساب والبريد وأندرويد وآيفون. تُسجَّل الإذاعة مباشرة من البث دون فقدان أو ضوضاء.'],
  'Sviluppata da {} · {}': ['Developed by {} · {}', 'Développée par {} · {}', 'Desarrollada por {} · {}', 'Entwickelt von {} · {}', 'تطوير {} · {}'],
  // pagina Registrate
  'Nessuna registrazione.\nAscolta una radio e premi ● Registra.': ['No recordings yet.\nPlay a station and press ● Record.', 'Aucun enregistrement.\nÉcoute une radio et appuie sur ● Enregistrer.', 'Ninguna grabación.\nEscucha una radio y pulsa ● Grabar.', 'Noch keine Aufnahmen.\nHöre einen Sender und drücke ● Aufnehmen.', 'لا توجد تسجيلات.\nاستمع إلى إذاعة واضغط ● تسجيل.'],
  'Tutte': ['All', 'Toutes', 'Todas', 'Alle', 'الكل'],
  'Pro': ['Pro', 'Pro', 'Pro', 'Pro', 'Pro'],
  'Modifica / taglia': ['Edit / cut', 'Modifier / couper', 'Editar / cortar', 'Bearbeiten / schneiden', 'تعديل / قص'],
  'Rinomina': ['Rename', 'Renommer', 'Renombrar', 'Umbenennen', 'إعادة تسمية'],
  'Condividi (WhatsApp, email…)': ['Share (WhatsApp, email…)', 'Partager (WhatsApp, e-mail…)', 'Compartir (WhatsApp, correo…)', 'Teilen (WhatsApp, E-Mail…)', 'مشاركة (واتساب، بريد…)'],
  'Elimina': ['Delete', 'Supprimer', 'Eliminar', 'Löschen', 'حذف'],
  'Eliminare?': ['Delete?', 'Supprimer ?', '¿Eliminar?', 'Löschen?', 'حذف؟'],
  '"{}" verrà eliminata definitivamente.': ['"{}" will be deleted permanently.', '« {} » sera supprimé définitivement.', '"{}" se eliminará definitivamente.', '„{}" wird endgültig gelöscht.', 'سيُحذف "{}" نهائيًا.'],
  'Annulla': ['Cancel', 'Annuler', 'Cancelar', 'Abbrechen', 'إلغاء'],
  'Salva': ['Save', 'Enregistrer', 'Guardar', 'Speichern', 'حفظ'],
  'Rinomina non riuscita': ['Rename failed', 'Échec du renommage', 'No se pudo renombrar', 'Umbenennen fehlgeschlagen', 'فشلت إعادة التسمية'],
  'Condivisione non riuscita': ['Sharing failed', 'Échec du partage', 'No se pudo compartir', 'Teilen fehlgeschlagen', 'فشلت المشاركة'],
  'Impossibile riprodurre il file': ['Can\'t play the file', 'Impossible de lire le fichier', 'No se puede reproducir el archivo', 'Datei kann nicht abgespielt werden', 'تعذّر تشغيل الملف'],
  'Ferma prima la registrazione': ['Stop the recording first', 'Arrête d\'abord l\'enregistrement', 'Detén primero la grabación', 'Stoppe zuerst die Aufnahme', 'أوقف التسجيل أولًا'],
  'Per la bandiera scrivi il paese con la tastiera (es. Spain → 🇪🇸)': ['For the flag, type the country on your keyboard (e.g. Spain → 🇪🇸)', 'Pour le drapeau, tape le pays au clavier (ex. Spain → 🇪🇸)', 'Para la bandera, escribe el país con el teclado (ej. Spain → 🇪🇸)', 'Für die Flagge das Land auf der Tastatur tippen (z. B. Spain → 🇪🇸)', 'للعلم اكتب اسم البلد بلوحة المفاتيح (مثال Spain → 🇪🇸)'],
  'Con Pro scegli tutte le qualità audio, da 10 a 56 MB l\'ora.': ['With Pro you choose every audio quality, from 10 to 56 MB per hour.', 'Avec Pro, choisis toutes les qualités audio, de 10 à 56 Mo par heure.', 'Con Pro eliges todas las calidades de audio, de 10 a 56 MB por hora.', 'Mit Pro wählst du jede Audioqualität, von 10 bis 56 MB pro Stunde.', 'مع Pro اختر كل جودات الصوت، من 10 إلى 56 MB في الساعة.'],
  'L\'editor per tagliare e unire è incluso in Pro.': ['The editor to cut and join is included in Pro.', 'L\'éditeur pour couper et assembler est inclus dans Pro.', 'El editor para cortar y unir está incluido en Pro.', 'Der Editor zum Schneiden und Verbinden ist in Pro enthalten.', 'محرر القص والدمج متاح في Pro.'],
  // preferiti
  'Tocca il ♡ accanto a una radio per salvarla qui.': ['Tap the ♡ next to a station to save it here.', 'Touche le ♡ à côté d\'une radio pour l\'enregistrer ici.', 'Toca el ♡ junto a una radio para guardarla aquí.', 'Tippe auf ♡ neben einem Sender, um ihn hier zu speichern.', 'اضغط ♡ بجانب إذاعة لحفظها هنا.'],
  'Ascoltate di recente': ['Recently played', 'Écoutées récemment', 'Escuchadas recientemente', 'Zuletzt gehört', 'استمعت إليها مؤخرًا'],
  'Cancella': ['Clear', 'Effacer', 'Borrar', 'Löschen', 'مسح'],
  // cerca
  'Radio': ['Stations', 'Radios', 'Radios', 'Sender', 'إذاعات'],
  'Paesi': ['Countries', 'Pays', 'Países', 'Länder', 'الدول'],
  'Generi': ['Genres', 'Genres', 'Géneros', 'Genres', 'الأنواع'],
  'Nome della radio o città': ['Station name or city', 'Nom de la radio ou ville', 'Nombre de la radio o ciudad', 'Sendername oder Stadt', 'اسم الإذاعة أو المدينة'],
  'Paese: Marocco, Italia, Egypt…': ['Country: Morocco, Italy, Egypt…', 'Pays : Maroc, Italie, Égypte…', 'País: Marruecos, Italia, Egipto…', 'Land: Marokko, Italien, Ägypten…', 'البلد: المغرب، إيطاليا، مصر…'],
  'Genere: jazz, news, quran…': ['Genre: jazz, news, quran…', 'Genre : jazz, news, coran…', 'Género: jazz, noticias, corán…', 'Genre: Jazz, News, Koran…', 'النوع: جاز، أخبار، قرآن…'],
  'Le più ascoltate nel mondo': ['Most played worldwide', 'Les plus écoutées au monde', 'Las más escuchadas del mundo', 'Weltweit am meisten gehört', 'الأكثر استماعًا في العالم'],
  'Nessuna radio trovata.\nProva un nome più corto (es. «Medi» invece di «Medi1»).': ['No stations found.\nTry a shorter name (e.g. "Medi" instead of "Medi1").', 'Aucune radio trouvée.\nEssaie un nom plus court (ex. « Medi » au lieu de « Medi1 »).', 'No se encontraron radios.\nPrueba un nombre más corto (ej. «Medi» en vez de «Medi1»).', 'Keine Sender gefunden.\nVersuche einen kürzeren Namen (z. B. „Medi" statt „Medi1").', 'لم يُعثر على إذاعات.\nجرّب اسمًا أقصر (مثل «Medi» بدل «Medi1»).'],
  'Nessuna radio trovata': ['No stations found', 'Aucune radio trouvée', 'No se encontraron radios', 'Keine Sender gefunden', 'لم يُعثر على إذاعات'],
  'Nessun paese trovato': ['No countries found', 'Aucun pays trouvé', 'No se encontraron países', 'Keine Länder gefunden', 'لم يُعثر على دول'],
  'Paesi non caricati, riprova': ['Countries not loaded, try again', 'Pays non chargés, réessaie', 'Países no cargados, reintenta', 'Länder nicht geladen, erneut versuchen', 'لم تُحمَّل الدول، أعد المحاولة'],
  'Non caricato, riprova': ['Not loaded, try again', 'Non chargé, réessaie', 'No cargado, reintenta', 'Nicht geladen, erneut versuchen', 'لم يُحمَّل، أعد المحاولة'],
  'Ricerca non riuscita. Controlla la connessione.': ['Search failed. Check your connection.', 'Recherche échouée. Vérifie la connexion.', 'Búsqueda fallida. Revisa la conexión.', 'Suche fehlgeschlagen. Prüfe die Verbindung.', 'فشل البحث. تحقّق من الاتصال.'],
  'Filtra {} radio (nome, città, genere)': ['Filter {} stations (name, city, genre)', 'Filtrer {} radios (nom, ville, genre)', 'Filtrar {} radios (nombre, ciudad, género)', '{} Sender filtern (Name, Stadt, Genre)', 'تصفية {} إذاعة (الاسم، المدينة، النوع)'],
  '{} radio': ['{} stations', '{} radios', '{} radios', '{} Sender', '{} إذاعة'],
  'Classica': ['Classical', 'Classique', 'Clásica', 'Klassik', 'كلاسيكية'],
  'Arabo': ['Arabic', 'Arabe', 'Árabe', 'Arabisch', 'عربي'],
  'Corano': ['Quran', 'Coran', 'Corán', 'Koran', 'القرآن'],
  'Italiano': ['Italian', 'Italien', 'Italiano', 'Italienisch', 'إيطالي'],
  'Latino': ['Latin', 'Latino', 'Latino', 'Latin', 'لاتيني'],
  'Anni 80': ['80s', 'Années 80', 'Años 80', '80er', 'الثمانينات'],
  // abbonamento
  'Senza pubblicità e senza limiti con Pro': ['No ads and no limits with Pro', 'Sans pub et sans limites avec Pro', 'Sin anuncios y sin límites con Pro', 'Ohne Werbung und ohne Limits mit Pro', 'بلا إعلانات وبلا حدود مع Pro'],
  'Registra senza limiti, programma i tuoi programmi preferiti, niente pubblicità.': ['Record without limits, schedule your favourite shows, no ads.', 'Enregistre sans limite, programme tes émissions préférées, sans pub.', 'Graba sin límites, programa tus programas favoritos, sin anuncios.', 'Ohne Limit aufnehmen, Lieblingssendungen planen, keine Werbung.', 'سجّل بلا حدود، جدول برامجك المفضلة، بلا إعلانات.'],
  'Registrazione illimitata, anche di ore': ['Unlimited recording, even for hours', 'Enregistrement illimité, même des heures', 'Grabación ilimitada, incluso de horas', 'Unbegrenzte Aufnahme, auch stundenlang', 'تسجيل غير محدود، حتى لساعات'],
  'Registrazioni programmate: partono da sole anche ad app chiusa': ['Scheduled recordings: they start on their own, even with the app closed', 'Enregistrements programmés : ils démarrent seuls, même app fermée', 'Grabaciones programadas: empiezan solas, incluso con la app cerrada', 'Geplante Aufnahmen: starten von selbst, auch bei geschlossener App', 'تسجيلات مجدولة: تبدأ تلقائيًا حتى والتطبيق مغلق'],
  '«Ogni giorno» per il tuo programma fisso': ['"Every day" for your regular show', '« Tous les jours » pour ton émission habituelle', '«Cada día» para tu programa fijo', '„Jeden Tag" für deine feste Sendung', '«كل يوم» لبرنامجك الثابت'],
  'Editor: taglia e unisci': ['Editor: cut and join', 'Éditeur : couper et assembler', 'Editor: cortar y unir', 'Editor: schneiden und verbinden', 'المحرر: قص ودمج'],
  'Tutte le qualità audio, da 10 a 56 MB l\'ora': ['Every audio quality, from 10 to 56 MB per hour', 'Toutes les qualités audio, de 10 à 56 Mo par heure', 'Todas las calidades de audio, de 10 a 56 MB por hora', 'Jede Audioqualität, von 10 bis 56 MB pro Stunde', 'كل جودات الصوت، من 10 إلى 56 MB في الساعة'],
  'Nessuna pubblicità': ['No ads', 'Aucune publicité', 'Sin anuncios', 'Keine Werbung', 'بلا إعلانات'],
  'Annuale · risparmi il 66%': ['Yearly · save 66%', 'Annuel · économise 66 %', 'Anual · ahorra un 66 %', 'Jährlich · spare 66 %', 'سنوي · وفّر 66%'],
  '0,33 € al mese · 7 giorni gratis': ['€0.33 per month · 7 days free', '0,33 € par mois · 7 jours gratuits', '0,33 € al mes · 7 días gratis', '0,33 € pro Monat · 7 Tage gratis', '0.33 € شهريًا · 7 أيام مجانًا'],
  'Mensile': ['Monthly', 'Mensuel', 'Mensual', 'Monatlich', 'شهري'],
  'disdici quando vuoi': ['cancel anytime', 'résilie quand tu veux', 'cancela cuando quieras', 'jederzeit kündbar', 'ألغِ متى شئت'],
  'Prova gratis 7 giorni': ['Try 7 days free', 'Essai gratuit 7 jours', 'Prueba gratis 7 días', '7 Tage gratis testen', 'جرّب 7 أيام مجانًا'],
  'Abbonati a 0,99 € al mese': ['Subscribe for €0.99 per month', 'S\'abonner pour 0,99 € par mois', 'Suscríbete por 0,99 € al mes', 'Für 0,99 € im Monat abonnieren', 'اشترك بـ 0.99 € شهريًا'],
  'Poi 3,99 € l\'anno. Disdici quando vuoi dallo store.': ['Then €3.99 per year. Cancel anytime in the store.', 'Puis 3,99 € par an. Résilie quand tu veux depuis le store.', 'Luego 3,99 € al año. Cancela cuando quieras desde la tienda.', 'Danach 3,99 € pro Jahr. Jederzeit im Store kündbar.', 'ثم 3.99 € سنويًا. ألغِ متى شئت من المتجر.'],
  'Si rinnova ogni mese. Disdici quando vuoi dallo store.': ['Renews every month. Cancel anytime in the store.', 'Se renouvelle chaque mois. Résilie quand tu veux depuis le store.', 'Se renueva cada mes. Cancela cuando quieras desde la tienda.', 'Verlängert sich monatlich. Jederzeit im Store kündbar.', 'يتجدد كل شهر. ألغِ متى شئت من المتجر.'],
  'L\'abbonamento si attiva con l\'uscita su AppGallery e Galaxy Store. Grazie!': ['The subscription will be available once the app is on AppGallery and Galaxy Store. Thank you!', 'L\'abonnement sera disponible à la sortie sur AppGallery et Galaxy Store. Merci !', 'La suscripción estará disponible con la salida en AppGallery y Galaxy Store. ¡Gracias!', 'Das Abo ist verfügbar, sobald die App in AppGallery und Galaxy Store erscheint. Danke!', 'سيتوفر الاشتراك عند صدور التطبيق على AppGallery وGalaxy Store. شكرًا!'],
  'Ripristina acquisto · Termini: {} · Privacy: {}\nSviluppata da {} · {}': ['Restore purchase · Terms: {} · Privacy: {}\nDeveloped by {} · {}', 'Restaurer l\'achat · Conditions : {} · Confidentialité : {}\nDéveloppée par {} · {}', 'Restaurar compra · Términos: {} · Privacidad: {}\nDesarrollada por {} · {}', 'Kauf wiederherstellen · AGB: {} · Datenschutz: {}\nEntwickelt von {} · {}', 'استعادة الشراء · الشروط: {} · الخصوصية: {}\nتطوير {} · {}'],
  'Le registrazioni programmate sono incluse in Pro. Provalo gratis per 7 giorni.': ['Scheduled recordings are included in Pro. Try it free for 7 days.', 'Les enregistrements programmés sont inclus dans Pro. Essaie-le gratuitement 7 jours.', 'Las grabaciones programadas están incluidas en Pro. Pruébalo gratis 7 días.', 'Geplante Aufnahmen sind in Pro enthalten. 7 Tage gratis testen.', 'التسجيلات المجدولة متاحة في Pro. جرّبه مجانًا 7 أيام.'],
  // programmazione
  'Cambia': ['Change', 'Changer', 'Cambiar', 'Ändern', 'تغيير'],
  'Giorno': ['Day', 'Jour', 'Día', 'Tag', 'اليوم'],
  'Inizio': ['Start', 'Début', 'Inicio', 'Start', 'البداية'],
  'Fine': ['End', 'Fin', 'Fin', 'Ende', 'النهاية'],
  'Adesso': ['Now', 'Maintenant', 'Ahora', 'Jetzt', 'الآن'],
  'Oggi': ['Today', 'Aujourd\'hui', 'Hoy', 'Heute', 'اليوم'],
  'Domani': ['Tomorrow', 'Demain', 'Mañana', 'Morgen', 'غدًا'],
  'oggi': ['today', 'aujourd\'hui', 'hoy', 'heute', 'اليوم'],
  'domani': ['tomorrow', 'demain', 'mañana', 'morgen', 'غدًا'],
  'Ogni giorno': ['Every day', 'Tous les jours', 'Cada día', 'Jeden Tag', 'كل يوم'],
  'Scrivi la radio, es. Fox News': ['Type the station, e.g. Fox News', 'Écris la radio, ex. Fox News', 'Escribe la radio, ej. Fox News', 'Sender eingeben, z. B. Fox News', 'اكتب اسم الإذاعة، مثل Fox News'],
  'Scegli prima la radio': ['Choose the station first', 'Choisis d\'abord la radio', 'Elige primero la radio', 'Wähle zuerst den Sender', 'اختر الإذاعة أولًا'],
  'Salvo…': ['Saving…', 'Enregistrement…', 'Guardando…', 'Speichern…', 'جارٍ الحفظ…'],
  'Inizia a registrare': ['Start recording', 'Commencer l\'enregistrement', 'Empezar a grabar', 'Aufnahme starten', 'ابدأ التسجيل'],
  'Programma alle {}': ['Schedule at {}', 'Programmer à {}', 'Programar a las {}', 'Planen für {}', 'جدولة عند {}'],
  'Da adesso alle {} del giorno dopo · circa {} MB': ['From now to {} the next day · about {} MB', 'De maintenant à {} le lendemain · environ {} Mo', 'Desde ahora hasta las {} del día siguiente · unos {} MB', 'Ab jetzt bis {} am nächsten Tag · ca. {} MB', 'من الآن حتى {} في اليوم التالي · حوالي {} MB'],
  'Da adesso alle {} · circa {} MB': ['From now to {} · about {} MB', 'De maintenant à {} · environ {} Mo', 'Desde ahora hasta las {} · unos {} MB', 'Ab jetzt bis {} · ca. {} MB', 'من الآن حتى {} · حوالي {} MB'],
  '{} dalle {} alle {} del giorno dopo · circa {} MB': ['{} from {} to {} the next day · about {} MB', '{} de {} à {} le lendemain · environ {} Mo', '{} de {} a {} del día siguiente · unos {} MB', '{} von {} bis {} am nächsten Tag · ca. {} MB', '{} من {} حتى {} في اليوم التالي · حوالي {} MB'],
  '{} dalle {} alle {} · circa {} MB': ['{} from {} to {} · about {} MB', '{} de {} à {} · environ {} Mo', '{} de {} a {} · unos {} MB', '{} von {} bis {} · ca. {} MB', '{} من {} حتى {} · حوالي {} MB'],
  'Orario già occupato': ['Time slot already taken', 'Créneau déjà occupé', 'Horario ya ocupado', 'Zeitfenster bereits belegt', 'الوقت محجوز مسبقًا'],
  'C\'è già «{}» dalle {} alle {}.\nSi registra una radio alla volta.': ['"{}" is already scheduled from {} to {}.\nOne station is recorded at a time.', '« {} » est déjà programmé de {} à {}.\nUne seule radio à la fois.', 'Ya está «{}» de {} a {}.\nSe graba una radio a la vez.', '„{}" ist schon von {} bis {} geplant.\nEs wird ein Sender nach dem anderen aufgenommen.', 'يوجد بالفعل «{}» من {} حتى {}.\nيُسجَّل إذاعة واحدة في كل مرة.'],
  'Sostituisci': ['Replace', 'Remplacer', 'Sustituir', 'Ersetzen', 'استبدال'],
  'Registrazione iniziata: {}, fino alle {}': ['Recording started: {}, until {}', 'Enregistrement démarré : {}, jusqu\'à {}', 'Grabación iniciada: {}, hasta las {}', 'Aufnahme gestartet: {}, bis {}', 'بدأ التسجيل: {}، حتى {}'],
  'Programmata: {}, {} {} → {}': ['Scheduled: {}, {} {} → {}', 'Programmé : {}, {} {} → {}', 'Programada: {}, {} {} → {}', 'Geplant: {}, {} {} → {}', 'تمت الجدولة: {}، {} {} → {}'],
  'Non riuscito, riprova': ['Failed, try again', 'Échec, réessaie', 'No se pudo, reintenta', 'Fehlgeschlagen, erneut versuchen', 'فشل، أعد المحاولة'],
  'Sta registrando · fino alle {}': ['Recording · until {}', 'Enregistre · jusqu\'à {}', 'Grabando · hasta las {}', 'Nimmt auf · bis {}', 'يسجّل · حتى {}'],
  '{} {} → {} · {}': ['{} {} → {} · {}', '{} {} → {} · {}', '{} {} → {} · {}', '{} {} → {} · {}', '{} {} → {} · {}'],
  'Ferma': ['Stop', 'Arrêter', 'Detener', 'Stoppen', 'إيقاف'],
  '1 ora': ['1 hour', '1 heure', '1 hora', '1 Stunde', 'ساعة واحدة'],
  '{} ore': ['{} hours', '{} heures', '{} horas', '{} Stunden', '{} ساعات'],
  // aggiornamento
  'Nuova versione disponibile': ['New version available', 'Nouvelle version disponible', 'Nueva versión disponible', 'Neue Version verfügbar', 'إصدار جديد متاح'],
  'Aggiorna ora': ['Update now', 'Mettre à jour', 'Actualizar ahora', 'Jetzt aktualisieren', 'حدّث الآن'],
  'Più tardi': ['Later', 'Plus tard', 'Más tarde', 'Später', 'لاحقًا'],
  'Scarico l\'aggiornamento…': ['Downloading the update…', 'Téléchargement de la mise à jour…', 'Descargando la actualización…', 'Update wird geladen…', 'جارٍ تنزيل التحديث…'],
  'Apro l\'installazione…': ['Opening the installer…', 'Ouverture de l\'installation…', 'Abriendo la instalación…', 'Installation wird geöffnet…', 'جارٍ فتح التثبيت…'],
  'Download non riuscito. Controlla internet e riprova.': ['Download failed. Check your internet and try again.', 'Téléchargement échoué. Vérifie Internet et réessaie.', 'Descarga fallida. Revisa internet e inténtalo de nuevo.', 'Download fehlgeschlagen. Prüfe das Internet und versuche es erneut.', 'فشل التنزيل. تحقّق من الإنترنت وحاول مجددًا.'],
  'Tocca «Installa» nella finestra di Android. Le registrazioni restano dove sono.': ['Tap "Install" in the Android window. Your recordings stay where they are.', 'Touche « Installer » dans la fenêtre Android. Tes enregistrements restent en place.', 'Toca «Instalar» en la ventana de Android. Tus grabaciones se quedan donde están.', 'Tippe im Android-Fenster auf „Installieren". Deine Aufnahmen bleiben erhalten.', 'اضغط «تثبيت» في نافذة أندرويد. تبقى تسجيلاتك كما هي.'],
  '{} di {} MB': ['{} of {} MB', '{} sur {} Mo', '{} de {} MB', '{} von {} MB', '{} من {} MB'],
  'Riprova ': ['Try again', 'Réessayer', 'Reintentar', 'Erneut versuchen', 'أعد المحاولة'],
  // editor
  'Analizzo l\'audio…': ['Analysing the audio…', 'Analyse de l\'audio…', 'Analizando el audio…', 'Audio wird analysiert…', 'جارٍ تحليل الصوت…'],
  'Ascolta selezione': ['Play selection', 'Écouter la sélection', 'Escuchar selección', 'Auswahl abspielen', 'استمع إلى التحديد'],
  'Comprimo…': ['Compressing…', 'Compression…', 'Comprimiendo…', 'Komprimiere…', 'جارٍ الضغط…'],
  'Deseleziona': ['Deselect', 'Désélectionner', 'Deseleccionar', 'Auswahl aufheben', 'إلغاء التحديد'],
  'Errore nel salvataggio: {}': ['Error while saving: {}', 'Erreur d\'enregistrement : {}', 'Error al guardar: {}', 'Fehler beim Speichern: {}', 'خطأ في الحفظ: {}'],
  'Esci': ['Leave', 'Quitter', 'Salir', 'Verlassen', 'خروج'],
  'Impossibile aprire il file: {}': ['Can\'t open the file: {}', 'Impossible d\'ouvrir le fichier : {}', 'No se puede abrir el archivo: {}', 'Datei kann nicht geöffnet werden: {}', 'تعذّر فتح الملف: {}'],
  'Ingrandisci': ['Zoom in', 'Agrandir', 'Ampliar', 'Vergrößern', 'تكبير'],
  'Riduci': ['Zoom out', 'Réduire', 'Reducir', 'Verkleinern', 'تصغير'],
  'Le modifiche andranno perse.': ['Your changes will be lost.', 'Les modifications seront perdues.', 'Los cambios se perderán.', 'Die Änderungen gehen verloren.', 'ستفقد التعديلات.'],
  'Nessuna modifica da salvare': ['No changes to save', 'Aucune modification à enregistrer', 'No hay cambios que guardar', 'Keine Änderungen zu speichern', 'لا توجد تعديلات للحفظ'],
  'Non puoi togliere tutto l\'audio': ['You can\'t remove all the audio', 'Tu ne peux pas retirer tout l\'audio', 'No puedes quitar todo el audio', 'Du kannst nicht das ganze Audio entfernen', 'لا يمكنك حذف الصوت بالكامل'],
  'Nuova durata: {}': ['New length: {}', 'Nouvelle durée : {}', 'Nueva duración: {}', 'Neue Länge: {}', 'المدة الجديدة: {}'],
  'Preparo l\'anteprima…': ['Preparing preview…', 'Préparation de l\'aperçu…', 'Preparando la vista previa…', 'Vorschau wird vorbereitet…', 'جارٍ تجهيز المعاينة…'],
  'Preparo l\'audio… {}%': ['Preparing audio… {}%', 'Préparation de l\'audio… {}%', 'Preparando el audio… {}%', 'Audio wird vorbereitet… {}%', 'جارٍ تجهيز الصوت… {}%'],
  'Resta': ['Stay', 'Rester', 'Quedarse', 'Bleiben', 'البقاء'],
  'Ripeti': ['Redo', 'Rétablir', 'Rehacer', 'Wiederholen', 'إعادة'],
  'Salva come copia': ['Save as copy', 'Enregistrer une copie', 'Guardar como copia', 'Als Kopie speichern', 'حفظ كنسخة'],
  'Salva modifiche': ['Save changes', 'Enregistrer les modifications', 'Guardar cambios', 'Änderungen speichern', 'حفظ التعديلات'],
  'Seleziona tutto': ['Select all', 'Tout sélectionner', 'Seleccionar todo', 'Alles auswählen', 'تحديد الكل'],
  'Selezione {}': ['Selection {}', 'Sélection {}', 'Selección {}', 'Auswahl {}', 'التحديد {}'],
  'Taglia dopo il cursore': ['Cut after cursor', 'Couper après le curseur', 'Cortar tras el cursor', 'Nach dem Cursor schneiden', 'قص بعد المؤشر'],
  'Taglia prima del cursore': ['Cut before cursor', 'Couper avant le curseur', 'Cortar antes del cursor', 'Vor dem Cursor schneiden', 'قص قبل المؤشر'],
  'Taglia selezione e unisci': ['Cut selection and join', 'Couper la sélection et assembler', 'Cortar selección y unir', 'Auswahl schneiden und verbinden', 'قص التحديد ودمج'],
  'Tagliato {} e unito': ['Cut {} and joined', '{} coupé et assemblé', 'Cortado {} y unido', '{} geschnitten und verbunden', 'تم قص {} ودمجه'],
  'Tieni solo selezione': ['Keep selection only', 'Garder la sélection', 'Mantener solo la selección', 'Nur Auswahl behalten', 'احتفظ بالتحديد فقط'],
  'Tutto': ['All', 'Tout', 'Todo', 'Alles', 'الكل'],
  'Uscire senza salvare?': ['Leave without saving?', 'Quitter sans enregistrer ?', '¿Salir sin guardar?', 'Ohne Speichern verlassen?', 'الخروج دون حفظ؟'],
  'Zoom sulla selezione': ['Zoom to selection', 'Zoom sur la sélection', 'Zoom a la selección', 'Auf Auswahl zoomen', 'تكبير التحديد'],
  'originale {}': ['original {}', 'original {}', 'original {}', 'Original {}', 'الأصلي {}'],
  'visibili {}': ['visible {}', 'visible {}', 'visible {}', 'sichtbar {}', 'المرئي {}'],
  '{} punti uniti automaticamente (dissolvenza 5 ms, senza click)': ['{} joins smoothed automatically (5 ms fade, no clicks)', '{} raccords lissés automatiquement (fondu 5 ms, sans clic)', '{} uniones suavizadas automáticamente (fundido 5 ms, sin clics)', '{} Übergänge automatisch geglättet (5 ms Blende, ohne Klicks)', 'تم دمج {} نقاط تلقائيًا (تلاشٍ 5 مللي ثانية، بلا نقرات)'],
  'Tocca per spostare il cursore. Due dita per lo zoom.': ['Tap to move the cursor. Two fingers to zoom.', 'Touche pour déplacer le curseur. Deux doigts pour zoomer.', 'Toca para mover el cursor. Dos dedos para el zoom.', 'Tippen, um den Cursor zu bewegen. Zwei Finger zum Zoomen.', 'اضغط لتحريك المؤشر. إصبعان للتكبير.'],
};
