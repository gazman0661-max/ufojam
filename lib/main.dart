import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'legal.dart';
import 'progress.dart';
import 'settings.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Progress.load();
  await Settings.load();
  await Legal.load();
  await Audio.init();
  runApp(const UfoBusJamApp());
}

class UfoBusJamApp extends StatelessWidget {
  const UfoBusJamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UFO Bus Jam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C4DFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
