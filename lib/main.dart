import 'package:flutter/material.dart';
import 'data/controller.dart';
import 'ui/auth.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(MedicineTrackerApp(controller: controller));
  await controller.initialize();
}

class MedicineTrackerApp extends StatelessWidget {
  const MedicineTrackerApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff176b60),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Medicine Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xfff6f8f7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff6f8f7),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
        ),
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : controller.signedIn
            ? HomeScreen(app: controller)
            : AuthScreen(app: controller),
      ),
    );
  }
}
