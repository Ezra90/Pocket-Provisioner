import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/app_directories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Move any files from legacy storage locations into the canonical
  // Pocket-Provisioner/ folder before the UI starts serving them.
  await AppDirectories.migrateToExternal();
  runApp(const MaterialApp(
    title: 'Pocket-Provisioner',
    debugShowCheckedModeBanner: false,
    home: DashboardScreen(),
  ));
}