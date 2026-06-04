import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: IntercomApp()));
}

class IntercomApp extends StatelessWidget {
  const IntercomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intercom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A1628),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          surface: Color(0xFF0D1F38),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A1628),
          foregroundColor: Color(0xFF00E5FF),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF001830),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
