// Web stub — delegates to shared_preferences (handled in storage_service.dart)
// These are never called directly on web; kIsWeb check routes to readFromPrefs/writeToPrefs.

Future<List<Map<String, dynamic>>> readFromFile(String key) async => [];
Future<void> writeToFile(String key, List<Map<String, dynamic>> data) async {}
Future<int> readFileBytesForKey(String key) async => 0;
