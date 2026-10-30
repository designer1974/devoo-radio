import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'favorites_page.dart';
import 'map_page.dart';
import 'player.dart';
import 'recorder.dart';
import 'recording.dart';
import 'recordings_page.dart';
import 'schedule.dart';
import 'search_page.dart';
import 'ads.dart';
import 'pro.dart';
import 'store.dart';
import 'update.dart';
import 'widgets.dart';
import 'i18n.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Un errore in un widget non deve mai chiudere l'app
    FlutterError.onError = (d) => FlutterError.presentError(d);
    ErrorWidget.builder = (_) => const SizedBox.shrink();
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.designer1974.devoo_radio.audio',
        androidNotificationChannelName: 'Devoo Radio',
        androidNotificationOngoing: true,
      );
    } catch (e) {
      debugPrint('Audio in background non disponibile: $e');
    }
    await Lang.i.init();
    await Pro.i.init();
    await Library.i.init();
    await RecSettings.i.load();
    runApp(const DevooRadioApp());
    unawaited(StationStore.i.init());
    unawaited(initAds());
    unawaited(RecController.i.recoverInterrupted());
  }, (error, stack) => debugPrint('Errore non gestito: $error'));
}

class DevooRadioApp extends StatelessWidget {
  const DevooRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF10151B),
    );
    return ListenableBuilder(
      listenable: Lang.i,
      builder: (context, _) => MaterialApp(
      title: Pro.i.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        focusColor: accent.withValues(alpha: 0.28), // si vede bene col telecomando della TV
      ),
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const HomeShell(),
      // lingue: anche l'arabo, scritto da destra a sinistra
      locale: Locale(Lang.i.code),
      supportedLocales: [for (final c in Lang.codes) Locale(c)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  StreamSubscription<String>? _errors;
  StreamSubscription<String>? _recMsgs;
  // tornando nell'app: aggiorna registrazioni e programmi (possono essere finiti ad app chiusa)
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: () {
    Recordings.i.reload();
    Schedules.i.reload();
  });

  @override
  void initState() {
    super.initState();
    _recMsgs = RecController.i.messages.listen(_snack);
    _life.hashCode; // avvia l'ascolto
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted && Pro.i.isProPackage) checkForUpdate(context); // solo la versione GitHub
    });
    Schedules.i.reload();
    _errors = RadioPlayer.i.errors.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _life.dispose();
    _recMsgs?.cancel();
    _errors?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, tab, _) => Scaffold(
        body: IndexedStack(
          index: tab,
          children: const [MapPage(), SearchPage(), FavoritesPage(), RecordingsPage()],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdBanner(),
            const RecBanner(),
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => tabIndex.value = i,
              destinations: [
                NavigationDestination(
                    icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: tr('Mappa')),
                NavigationDestination(icon: Icon(Icons.search), label: tr('Cerca')),
                NavigationDestination(
                    icon: Icon(Icons.favorite_border),
                    selectedIcon: Icon(Icons.favorite),
                    label: tr('Preferiti')),
                NavigationDestination(
                    icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: tr('Registrate')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
