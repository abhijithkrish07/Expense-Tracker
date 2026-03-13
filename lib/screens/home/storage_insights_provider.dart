// Storage insights provider: loads current storage metrics plus historical snapshots.
// Caveat: refresh updates snapshot history based on service-side deduping rules.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/storage_provider.dart';
import '../../services/storage_service.dart';

final storageInsightsProvider = FutureProvider<StorageInsightsWithHistory>(
  (ref) async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadStorageInsightsWithHistory();
  },
);
