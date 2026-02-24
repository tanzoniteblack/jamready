import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roller_derby_jam_timer/styles/track_background.dart';
import 'models/scoreboard_state.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ScoreboardState())],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roller Derby Scoreboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return PremiumBackground(child: child ?? const SizedBox.shrink());
      },
      home: const SettingsScreen(),
    );
  }
}
