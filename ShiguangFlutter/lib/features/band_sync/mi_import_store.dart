// ShiguangFlutter/lib/features/band_sync/mi_import_store.dart
// 手环导入去重账本：已导入 externalId 集合（SharedPreferences，非敏感数据）。
// 键名沿用 sg_band_imported_ids（HC 版同名账本，历史 id 不丢）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bandImportedIdsPrefKey = 'sg_band_imported_ids';

/// 账本上限：超出后淘汰最老的键；淘汰只影响去重精度，不影响数据安全。
const bandImportedIdsMax = 500;

class MiImportStore {
  MiImportStore({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  Future<Set<String>> load() async {
    final p = await _prefs();
    return (p.getStringList(bandImportedIdsPrefKey) ?? const <String>[]).toSet();
  }

  Future<void> addAll(Iterable<String> ids) async {
    final p = await _prefs();
    final merged = <String>[
      ...(p.getStringList(bandImportedIdsPrefKey) ?? const <String>[]),
      ...ids,
    ];
    final seen = <String>{};
    final kept = <String>[];
    for (final id in merged.reversed) {
      if (seen.add(id)) kept.add(id);
    }
    final trimmed =
        kept.take(bandImportedIdsMax).toList().reversed.toList(growable: false);
    await p.setStringList(bandImportedIdsPrefKey, trimmed);
  }
}

final miImportStoreProvider = Provider<MiImportStore>((ref) => MiImportStore());
