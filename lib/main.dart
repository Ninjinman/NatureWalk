import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data/species_database.dart';
import 'services/bgm.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await SpeciesDatabase.instance.initialize();
  runApp(const ProviderScope(child: NatureWalkApp()));
}

class NatureWalkApp extends StatelessWidget {
  const NatureWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NatureWalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8B96A),
          secondary: Color(0xFFE8B96A),
          surface: Color(0xFF0E0C09),
        ),
        scaffoldBackgroundColor: const Color(0xFF090806),
        textTheme: GoogleFonts.zenOldMinchoTextTheme(ThemeData.dark().textTheme),
      ),
      // 最初のタップで和風BGMを始める（ブラウザは操作の後でないと音を出せない）
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => Bgm.ensureStarted(),
        child: child,
      ),
      home: const HomeScreen(),
    );
  }
}
