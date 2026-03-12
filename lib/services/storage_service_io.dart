import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$name.json');
}

Future<List<Map<String, dynamic>>> readFromFile(String key) async {
  try {
    final file = await _file(key);
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    return List<Map<String, dynamic>>.from(jsonDecode(content) as List);
  } catch (_) {
    return [];
  }
}

Future<void> writeToFile(String key, List<Map<String, dynamic>> data) async {
  final file = await _file(key);
  await file.writeAsString(jsonEncode(data));
}
