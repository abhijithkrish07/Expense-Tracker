import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const _masterKeyStorageKey = 'storage_master_key_v1';
const _storageVersion = 1;

final _algorithm = AesGcm.with256bits();
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

Future<File> _file(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$name.bin');
}

Future<SecretKey> _getOrCreateMasterKey() async {
  final existing = await _secureStorage.read(key: _masterKeyStorageKey);
  if (existing != null && existing.isNotEmpty) {
    return SecretKey(base64Decode(existing));
  }

  final generated = await _algorithm.newSecretKey();
  final bytes = await generated.extractBytes();
  await _secureStorage.write(
    key: _masterKeyStorageKey,
    value: base64Encode(bytes),
  );
  return SecretKey(bytes);
}

/// Thrown when an encrypted file exists but cannot be decrypted.
/// This usually means the secure-storage key was lost (e.g. device reset,
/// or secure storage cleared during an OS upgrade).
class StorageDecryptionException implements Exception {
  final String key;
  const StorageDecryptionException(this.key);

  @override
  String toString() =>
      'StorageDecryptionException: cannot decrypt data for key "$key". '
      'The encryption key may have been lost.';
}

Future<List<Map<String, dynamic>>> readFromFile(String key) async {
  final file = await _file(key);
  if (!await file.exists()) return [];

  try {
    final envelopeRaw = await file.readAsString();
    if (envelopeRaw.isEmpty) return [];
    final envelope = jsonDecode(envelopeRaw) as Map<String, dynamic>;

    final version = envelope['v'];
    if (version != _storageVersion) return [];

    final nonce = base64Decode(envelope['n'] as String);
    final cipherText = base64Decode(envelope['c'] as String);
    final macBytes = base64Decode(envelope['t'] as String);

    final keyMaterial = await _getOrCreateMasterKey();
    final clearBytes = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: keyMaterial,
    );

    final jsonBytes = gzip.decode(clearBytes);
    final jsonString = utf8.decode(jsonBytes);
    return List<Map<String, dynamic>>.from(jsonDecode(jsonString) as List);
  } catch (e) {
    if (e is StorageDecryptionException) rethrow;
    throw StorageDecryptionException(key);
  }
}

Future<void> writeToFile(String key, List<Map<String, dynamic>> data) async {
  final file = await _file(key);
  final keyMaterial = await _getOrCreateMasterKey();
  final plainJson = jsonEncode(data);

  final compressed = gzip.encode(utf8.encode(plainJson));
  final nonce = _algorithm.newNonce();

  final sealed = await _algorithm.encrypt(
    compressed,
    secretKey: keyMaterial,
    nonce: nonce,
  );

  final envelope = jsonEncode({
    'v': _storageVersion,
    'n': base64Encode(sealed.nonce),
    'c': base64Encode(sealed.cipherText),
    't': base64Encode(sealed.mac.bytes),
  });

  await file.writeAsString(envelope, flush: true);
}

Future<int> readFileBytesForKey(String key) async {
  try {
    final file = await _file(key);
    if (!await file.exists()) return 0;
    return await file.length();
  } catch (_) {
    return 0;
  }
}

/// Encrypts [plainText] using the app's AES-256-GCM master key.
/// Returns the JSON envelope as a UTF-8 byte array (suitable for file writes).
Future<List<int>> encryptStringToBytes(String plainText) async {
  final keyMaterial = await _getOrCreateMasterKey();
  final compressed = gzip.encode(utf8.encode(plainText));
  final nonce = _algorithm.newNonce();

  final sealed = await _algorithm.encrypt(
    compressed,
    secretKey: keyMaterial,
    nonce: nonce,
  );

  final envelope = jsonEncode({
    'v': _storageVersion,
    'n': base64Encode(sealed.nonce),
    'c': base64Encode(sealed.cipherText),
    't': base64Encode(sealed.mac.bytes),
  });

  return utf8.encode(envelope);
}

/// Decrypts bytes previously produced by [encryptStringToBytes].
/// Returns null if decryption fails (wrong key, corrupt data, etc.).
Future<String?> decryptBytesToString(List<int> bytes) async {
  try {
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (envelope['v'] != _storageVersion) return null;

    final nonce = base64Decode(envelope['n'] as String);
    final cipherText = base64Decode(envelope['c'] as String);
    final macBytes = base64Decode(envelope['t'] as String);

    final keyMaterial = await _getOrCreateMasterKey();
    final clearBytes = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: keyMaterial,
    );

    return utf8.decode(gzip.decode(clearBytes));
  } catch (_) {
    return null;
  }
}
