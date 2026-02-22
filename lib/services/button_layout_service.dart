import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/button_key.dart';

class ButtonLayoutService {
  static const String _prefsKey = 'button_layouts'; // Key for the entire map in SharedPreferences
  static const String _labelOverridesKey = 'label_overrides'; // Per-device label overrides

  /// Loads the layout for a specific model.
  /// Returns an empty list if no layout saved for that model.
  static Future<List<ButtonKey>> getLayoutForModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    final String? allLayoutsJson = prefs.getString(_prefsKey);

    if (allLayoutsJson == null) {
      return <ButtonKey>[];
    }

    try {
      final Map<String, dynamic> allLayouts = json.decode(allLayoutsJson) as Map<String, dynamic>;
      final String? layoutJson = allLayouts[model] as String?;

      if (layoutJson == null) {
        return <ButtonKey>[];
      }

      final List<dynamic> decodedList = json.decode(layoutJson) as List<dynamic>;
      return decodedList.map((e) => ButtonKey.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    } catch (e) {
      // Corrupted data — safe fallback
      return <ButtonKey>[];
    }
  }

  /// Saves the layout for a specific model.
  /// Overwrites if exists, creates if new.
  static Future<void> saveLayoutForModel(String model, List<ButtonKey> layout) async {
    final prefs = await SharedPreferences.getInstance();
    final String? allLayoutsJson = prefs.getString(_prefsKey);

    Map<String, dynamic> allLayouts = allLayoutsJson != null
        ? json.decode(allLayoutsJson) as Map<String, dynamic>
        : <String, dynamic>{};

    // Sort layout by ID just in case
    layout.sort((a, b) => a.id.compareTo(b.id));

    allLayouts[model] = json.encode(layout.map((key) => key.toJson()).toList());

    await prefs.setString(_prefsKey, json.encode(allLayouts));
  }

  /// Optional: Clear all layouts (for debugging/reset)
  static Future<void> clearAllLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // ---------------------------------------------------------------------------
  // Per-device label overrides (used when button layout is carried over)
  // ---------------------------------------------------------------------------

  /// Returns the label overrides for a specific MAC address.
  /// Map key is the button key id (as String), value is the custom label.
  static Future<Map<String, String>> getLabelOverrides(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    final String? allOverridesJson = prefs.getString(_labelOverridesKey);
    if (allOverridesJson == null) return {};
    try {
      final Map<String, dynamic> all =
          json.decode(allOverridesJson) as Map<String, dynamic>;
      final raw = all[mac.toUpperCase()] as Map<String, dynamic>?;
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// Persists label overrides for a specific MAC address.
  static Future<void> saveLabelOverrides(
      String mac, Map<String, String> overrides) async {
    final prefs = await SharedPreferences.getInstance();
    final String? allOverridesJson = prefs.getString(_labelOverridesKey);
    Map<String, dynamic> all = allOverridesJson != null
        ? json.decode(allOverridesJson) as Map<String, dynamic>
        : {};
    all[mac.toUpperCase()] = overrides;
    await prefs.setString(_labelOverridesKey, json.encode(all));
  }
}
