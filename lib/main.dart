import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/app_directories.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Migrate user files from legacy internal storage to external storage
  // (accessible via Android file manager).  Runs once; safe on every launch.
  AppDirectories.migrateToExternal();
  runApp(const MaterialApp(
    title: 'Pocket Provisioner',
    debugShowCheckedModeBanner: false,
    home: DashboardScreen(),
  ));
}