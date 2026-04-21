import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/phonebook_entry.dart';
import 'app_directories.dart';

/// Handles generation and persistence of per-device phonebook XML files.
///
/// Files are stored in `<appDocuments>/phonebook/` as
/// `pb_<extension>.xml` and served by the provisioning server at
/// `/phonebook/pb_<extension>.xml`.
class PhonebookService {
  /// Saves a phonebook XML file for the given extension and returns the
  /// filename (without path) that was written, or `null` if [entries] is
  /// empty (in which case any existing file is deleted).
  ///
  /// [model] is used to select the appropriate XML vendor format:
  /// Yealink (default), Polycom VVX/Edge, or Cisco.
  static Future<String?> saveForExtension(
    String extension,
    List<PhonebookEntry> entries, {
    String displayName = '',
    String model = '',
  }) async {
    final dir = await _phonebookDir();
    final filename = 'pb_$extension.xml';
    final file = File(p.join(dir.path, filename));

    if (entries.isEmpty) {
      if (await file.exists()) await file.delete();
      return null;
    }

    final xml = generateXmlForModel(
      entries,
      model: model,
      displayName: displayName,
    );
    await file.writeAsString(xml, flush: true);
    return filename;
  }

  /// Deletes the phonebook XML file for [extension] if it exists.
  static Future<void> deleteForExtension(String extension) async {
    final dir = await _phonebookDir();
    final file = File(p.join(dir.path, 'pb_$extension.xml'));
    if (await file.exists()) await file.delete();
  }

  /// Returns the directory where phonebook XML files are stored,
  /// creating it if necessary.
  static Future<Directory> _phonebookDir() => AppDirectories.phonebookDir();

  // ─────────────────────────────────────────────────────────────────────────
  // XML generators
  // ─────────────────────────────────────────────────────────────────────────

  /// Dispatches to the correct vendor XML generator based on [model].
  ///
  /// - Polycom VVX / Edge E → [generatePolycomXml]
  /// - Cisco 7800 / 8800    → [generateCiscoXml]
  /// - All others (default) → [generateYealinkXml]
  static String generateXmlForModel(
    List<PhonebookEntry> entries, {
    String model = '',
    String displayName = '',
  }) {
    final m = model.toUpperCase();
    // Cisco: brand name, CP prefix, or 78xx/88xx model numbers
    if (m.contains('CISCO') ||
        m.startsWith('CP') ||
        RegExp(r'(?:^|[^0-9])(?:78|88)\d{2}(?:[^0-9]|$)').hasMatch(m)) {
      return generateCiscoXml(entries, displayName: displayName);
    }
    // Polycom / Poly Edge: brand name, VVX prefix, EDGE prefix, or OBi prefix
    if (m.contains('POLY') ||
        m.contains('VVX') ||
        m.contains('EDGE') ||
        m.startsWith('OBi')) {
      return generatePolycomXml(entries, displayName: displayName);
    }
    // Default: Yealink
    return generateYealinkXml(entries, displayName: displayName);
  }

  /// Generates a Yealink XML remote phonebook from [entries].
  ///
  /// Yealink remote phonebook format:
  /// ```xml
  /// <?xml version="1.0" encoding="UTF-8"?>
  /// <YealinkIPPhoneDirectory>
  ///   <DirectoryEntry>
  ///     <Name>Alice</Name>
  ///     <Telephone>101</Telephone>
  ///   </DirectoryEntry>
  /// </YealinkIPPhoneDirectory>
  /// ```
  static String generateYealinkXml(
    List<PhonebookEntry> entries, {
    String displayName = '',
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<YealinkIPPhoneDirectory>');
    if (displayName.isNotEmpty) {
      buf.writeln('  <!-- $displayName -->');
    }
    for (final e in entries) {
      buf.writeln('  <DirectoryEntry>');
      buf.writeln('    <Name>${_xmlEscape(e.name)}</Name>');
      buf.writeln('    <Telephone>${_xmlEscape(e.phone)}</Telephone>');
      if (e.group.isNotEmpty && e.group != 'All Contacts') {
        buf.writeln('    <Group>${_xmlEscape(e.group)}</Group>');
      }
      buf.writeln('  </DirectoryEntry>');
    }
    buf.writeln('</YealinkIPPhoneDirectory>');
    return buf.toString();
  }

  /// Generates a Polycom XML remote phonebook from [entries].
  ///
  /// Polycom directory format:
  /// ```xml
  /// <?xml version="1.0" standalone="yes"?>
  /// <directory>
  ///   <item_list>
  ///     <item><fn>Alice</fn><ct>101</ct></item>
  ///   </item_list>
  /// </directory>
  /// ```
  static String generatePolycomXml(
    List<PhonebookEntry> entries, {
    String displayName = '',
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" standalone="yes"?>');
    buf.writeln('<directory>');
    if (displayName.isNotEmpty) {
      buf.writeln('  <!-- $displayName -->');
    }
    buf.writeln('  <item_list>');
    for (final e in entries) {
      buf.writeln('    <item>');
      buf.writeln('      <fn>${_xmlEscape(e.name)}</fn>');
      buf.writeln('      <ct>${_xmlEscape(e.phone)}</ct>');
      if (e.group.isNotEmpty && e.group != 'All Contacts') {
        buf.writeln('      <sd>${_xmlEscape(e.group)}</sd>');
      }
      buf.writeln('    </item>');
    }
    buf.writeln('  </item_list>');
    buf.writeln('</directory>');
    return buf.toString();
  }

  /// Generates a Cisco XML directory from [entries].
  ///
  /// Cisco IP Phone Directory format:
  /// ```xml
  /// <CiscoIPPhoneDirectory>
  ///   <DirectoryEntry>
  ///     <Name>Alice</Name>
  ///     <Telephone>101</Telephone>
  ///   </DirectoryEntry>
  /// </CiscoIPPhoneDirectory>
  /// ```
  static String generateCiscoXml(
    List<PhonebookEntry> entries, {
    String displayName = '',
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<CiscoIPPhoneDirectory>');
    if (displayName.isNotEmpty) {
      buf.writeln('  <Title>${_xmlEscape(displayName)}</Title>');
      buf.writeln('  <Prompt>Select a contact</Prompt>');
    }
    for (final e in entries) {
      buf.writeln('  <DirectoryEntry>');
      buf.writeln('    <Name>${_xmlEscape(e.name)}</Name>');
      buf.writeln('    <Telephone>${_xmlEscape(e.phone)}</Telephone>');
      buf.writeln('  </DirectoryEntry>');
    }
    buf.writeln('</CiscoIPPhoneDirectory>');
    return buf.toString();
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
