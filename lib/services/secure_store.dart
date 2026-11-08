import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:shared_preferences/shared_preferences.dart';

/// 本地加密凭据仓。
///
/// - 常规模式：AES-256-CBC 加密后落盘，主密钥随机生成并单独存放，绝不打印明文。
/// - 临时模式 [ephemeral]：Key 只驻留内存，进程退出即销毁，不写磁盘。
/// - 多连接配置：id -> Key 的映射整体加密存放，切换配置不会丢失任何一份密钥。
/// - [destroy]：清除全部密钥与密文并轮换主密钥，旧密文永久不可解。
class SecureStore {
  static const _kCipher = 'vault.cipher';
  static const _kProfileKeys = 'vault.profile_keys';
  static const _kMaster = 'vault.master';
  static const _kIv = 'vault.iv';
  static const _kSettings = 'vault.settings';
  static const _kPluginCache = 'vault.plugin_cache';

  SharedPreferences? _prefs;
  enc.Key? _key;
  enc.IV? _iv;
  String? _memoryOnly;
  Map<String, String>? _memoryKeys;
  bool _ephemeral = false;

  SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) throw StateError('SecureStore 尚未初始化');
    return p;
  }

  bool get ephemeral => _ephemeral;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final ks = prefs.getString(_kMaster);
    final ivs = prefs.getString(_kIv);
    if (ks != null && ivs != null && ks.isNotEmpty && ivs.isNotEmpty) {
      try {
        _key = enc.Key.fromBase64(ks);
        _iv = enc.IV.fromBase64(ivs);
      } catch (_) {
        await _rotate();
      }
    } else {
      await _rotate();
    }
  }

  Future<void> _rotate() async {
    _key = enc.Key.fromSecureRandom(32);
    _iv = enc.IV.fromSecureRandom(16);
    await prefs.setString(_kMaster, _key!.base64);
    await prefs.setString(_kIv, _iv!.base64);
  }

  void setEphemeral(bool value) {
    _ephemeral = value;
  }

  Future<void> saveApiKey(String plain) async {
    if (_ephemeral) {
      _memoryOnly = plain;
      await prefs.remove(_kCipher);
      return;
    }
    final cipherText = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc))
        .encrypt(plain, iv: _iv!)
        .base64;
    await prefs.setString(_kCipher, cipherText);
    _memoryOnly = null;
  }

  /// 从加密持久化切换到内存态：全部明文搬进内存并抹掉磁盘密文。
  Future<void> moveToMemory() async {
    final keys = readProfileKeys();
    final single = readApiKey();
    _ephemeral = true;
    _memoryKeys = keys;
    _memoryOnly = single;
    await prefs.remove(_kCipher);
    await prefs.remove(_kProfileKeys);
  }

  /// 从内存态切回加密持久化。
  Future<void> moveToDisk() async {
    final keys = Map<String, String>.of(_memoryKeys ?? const {});
    _ephemeral = false;
    _memoryKeys = null;
    _memoryOnly = null;
    await saveProfileKeys(keys);
  }

  String readApiKey() {
    if (_ephemeral) return _memoryOnly ?? '';
    final cipherText = prefs.getString(_kCipher);
    if (cipherText == null || cipherText.isEmpty) return '';
    try {
      return enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc))
          .decrypt64(cipherText, iv: _iv!);
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------ 多连接配置密钥

  Future<void> saveProfileKeys(Map<String, String> keys) async {
    if (_ephemeral) {
      _memoryKeys = Map<String, String>.of(keys);
      await prefs.remove(_kProfileKeys);
      return;
    }
    final cipherText = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc))
        .encrypt(jsonEncode(keys), iv: _iv!)
        .base64;
    await prefs.setString(_kProfileKeys, cipherText);
    _memoryKeys = null;
  }

  /// 读取全部配置的密钥。兼容旧版单 Key 密文（作为 'default' 返回）。
  Map<String, String> readProfileKeys() {
    if (_ephemeral) return Map<String, String>.of(_memoryKeys ?? const {});
    final cipherText = prefs.getString(_kProfileKeys);
    if (cipherText != null && cipherText.isNotEmpty) {
      try {
        final plain = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc))
            .decrypt64(cipherText, iv: _iv!);
        final decoded = jsonDecode(plain);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    final legacy = readApiKey();
    if (legacy.isNotEmpty) return <String, String>{'default': legacy};
    return <String, String>{};
  }

  Future<void> destroy() async {
    _memoryOnly = null;
    _memoryKeys = null;
    await prefs.remove(_kCipher);
    await prefs.remove(_kProfileKeys);
    await prefs.remove(_kMaster);
    await prefs.remove(_kIv);
    _key = null;
    _iv = null;
    await _rotate();
  }

  String? loadSettings() => prefs.getString(_kSettings);

  Future<void> saveSettings(String json) => prefs.setString(_kSettings, json);

  String? loadPluginCache() => prefs.getString(_kPluginCache);

  Future<void> savePluginCache(String json) =>
      prefs.setString(_kPluginCache, json);

  Future<void> removePluginCache() => prefs.remove(_kPluginCache);
}
