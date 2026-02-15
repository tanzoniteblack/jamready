import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/scoreboard_state.dart';
import 'screens/jam_timer_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final hasHost = prefs.getString('server_host') != null;
  final hasPort = prefs.getString('server_port') != null;

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ScoreboardState())],
      child: MyApp(showSettings: !hasHost || !hasPort),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool showSettings;
  const MyApp({super.key, required this.showSettings});

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
      home: showSettings ? const SettingsScreen() : const JamTimerScreen(),
    );
  }
}
