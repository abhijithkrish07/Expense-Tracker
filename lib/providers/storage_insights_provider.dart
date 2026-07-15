import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_provider.dart';
import '../services/storage_service.dart';

final storageInsightsProvider = FutureProvider<StorageInsightsWithHistory>(
  (ref) async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadStorageInsightsWithHistory();
  },
);
