// Storage insights formatting helpers: keeps data formatting consistent across cards.
// Caveat: byte formatting uses binary units (base 1024), not decimal units.
String formatStorageBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  if (bytes <= 0) return '0 B';

  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }

  final precision = size >= 10 || unit == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unit]}';
}
