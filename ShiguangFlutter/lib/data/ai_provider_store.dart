// ShiguangFlutter/lib/data/ai_provider_store.dart
// 用户自带 AI 厂商配置的安全存储（M14-T3）。
//
// 为什么要单独一个存储：Key 是用户自己的钱，不能进 SharedPreferences（明文、
// 随备份导出），也不能随登录态一起被清（sg_token 过期不该丢 Key）。故与
// token_store.dart 同一套 flutter_secure_storage 用法，独立键
// sg_ai_provider_v1，落盘 JSON {enabled,id,model,key}。
//
// 容错基线：识菜是主链路，Key 配置只是可选增强。load() 对坏 JSON / 缺字段 /
// 读盘异常一律返回 null（按「未配置」处理），绝不把设置页的脏数据升级成
// 识菜失败；写失败才向上抛（用户点保存必须知道没存进去）。

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户自带厂商的一份配置（设置页的完整形态：开关 + 厂商 + 模型 + Key）。
class AiProviderConfig {
  const AiProviderConfig({
    required this.enabled,
    required this.id,
    required this.model,
    required this.key,
  });

  final bool enabled;
  final String id;
  final String model;
  final String key;

  /// 真正可用于请求的判定：开关开且三项齐全。设置页可保存半成品
  /// （例如先选厂商、还没填 Key），但扫描请求不能带上去。
  bool get isUsable =>
      enabled && id.isNotEmpty && model.isNotEmpty && key.isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'id': id, 'model': model, 'key': key};

  /// 解析失败 / 字段类型不符 → null（按未配置处理）。
  static AiProviderConfig? fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final enabled = m['enabled'];
      final id = m['id'];
      final model = m['model'];
      final key = m['key'];
      if (enabled is! bool ||
          id is! String ||
          model is! String ||
          key is! String) {
        return null;
      }
      return AiProviderConfig(enabled: enabled, id: id, model: model, key: key);
    } catch (_) {
      return null;
    }
  }
}

/// 存储接口：设置页与扫描链路只依赖它，单测可换内存实现。
abstract class AiProviderStore {
  /// 读不到 / 解析失败 / 读盘异常 → null（按未配置处理）。
  Future<AiProviderConfig?> load();
  Future<void> save(AiProviderConfig config);
  Future<void> clear();
}

/// 平台实现（真机）：flutter_secure_storage 持久化 JSON 字符串。
class SecureAiProviderStore implements AiProviderStore {
  SecureAiProviderStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String storageKey = 'sg_ai_provider_v1';

  @override
  Future<AiProviderConfig?> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return null;
      return AiProviderConfig.fromJson(raw);
    } catch (_) {
      return null; // 读盘失败按未配置处理，不打断识菜
    }
  }

  @override
  Future<void> save(AiProviderConfig config) =>
      _storage.write(key: storageKey, value: jsonEncode(config.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}

/// 组合根注入具体实现（root_container.dart）；此处不 new 平台对象，
/// 让 features/* 仅依赖 provider。
final aiProviderStoreProvider = Provider<AiProviderStore>(
    (ref) => throw UnimplementedError('组合根注入'));
