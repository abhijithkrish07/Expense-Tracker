import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

import '../services/storage_service_io.dart' as crypto;

const backupDirectoryName = 'ExpenseTracker_Backups';

/// Returns the platform-appropriate base path for backup files.
/// On Android this is the public Downloads folder (survives uninstall).
/// On iOS, getDownloadsDirectory() returns null so we fall back to the app
/// documents directory, which is the best available option.
Future<String> resolveDownloadsPath() async {
  final dir = await getDownloadsDirectory();
  if (dir != null) return dir.path;
  final fallback = await getApplicationDocumentsDirectory();
  return fallback.path;
}

/// Creates (if needed) and returns the backup directory.
Future<io.Directory> resolveBackupDirectory() async {
  final base = await resolveDownloadsPath();
  final dir = io.Directory('$base/$backupDirectoryName');
  await dir.create(recursive: true);
  return dir;
}

/// Writes [jsonString] to [file] encrypted with the app's AES-256-GCM key.
Future<void> writeEncryptedBackup(io.File file, String jsonString) async {
  final encryptedBytes = await crypto.encryptStringToBytes(jsonString);
  await file.writeAsBytes(encryptedBytes, flush: true);
}

/// Reads and decrypts a backup file written by [writeEncryptedBackup].
/// Falls back to reading as plain-text JSON to handle backups created before
/// encryption was introduced.
Future<String?> readEncryptedBackup(io.File file) async {
  if (!await file.exists()) return null;
  try {
    final bytes = await file.readAsBytes();
    // Try decryption first.
    final decrypted = await crypto.decryptBytesToString(bytes);
    if (decrypted != null) return decrypted;
    // Fallback: legacy plain-text backup.
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

/// Computes the delta between [previous] and [current] lists of JSON objects.
/// Returns upserts (new or changed rows) and a list of deleted IDs.
({List<Map<String, dynamic>> upsert, List<String> delete}) computeCollectionDelta(
  List<dynamic> previous,
  List<Map<String, dynamic>> current,
) {
  final prevById = <String, Map<String, dynamic>>{};
  for (final row in previous) {
    if (row is Map) {
      final normalized = Map<String, dynamic>.from(row);
      final id = normalized['id'];
      if (id is String && id.isNotEmpty) {
        prevById[id] = normalized;
      }
    }
  }

  final currentById = <String, Map<String, dynamic>>{};
  for (final row in current) {
    final id = row['id'];
    if (id is String && id.isNotEmpty) {
      currentById[id] = row;
    }
  }

  final upsert = <Map<String, dynamic>>[];
  final deleted = <String>[];

  for (final entry in currentById.entries) {
    final previousRow = prevById[entry.key];
    if (previousRow == null || jsonEncode(previousRow) != jsonEncode(entry.value)) {
      upsert.add(entry.value);
    }
  }

  for (final id in prevById.keys) {
    if (!currentById.containsKey(id)) {
      deleted.add(id);
    }
  }

  return (upsert: upsert, delete: deleted);
}
