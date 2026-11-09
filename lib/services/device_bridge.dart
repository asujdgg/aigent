import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/models.dart';

/// 本机设备信息的只读快照。
///
/// 真机数据来自 Android `[Build]` / `ActivityManager` / `BatteryManager` /
/// `StatFs`；在桌面、单元测试或通道未注册的环境里，退回 `dart:io` 能拿到的
/// 少量信息，保证上层永远拿得到一份可用的摘要，而不是抛异常。
class DeviceInfo {
  final Map<String, dynamic> raw;

  /// true 表示来自真实 Android 设备通道。
  final bool fromDevice;

  const DeviceInfo(this.raw, {this.fromDevice = true});

  static DeviceInfo fallback() => DeviceInfo(<String, dynamic>{
        'manufacturer': Platform.operatingSystem,
        'brand': Platform.operatingSystem,
        'model': Platform.localHostname,
        'android': Platform.operatingSystemVersion,
        'sdk': 0,
        'abis': <String>[],
        'cpuCores': Platform.numberOfProcessors,
        'totalMemMb': 0,
        'availMemMb': 0,
        'width': 0,
        'height': 0,
        'density': 0,
        'battery': -1,
        'storageTotalMb': 0,
        'storageFreeMb': 0,
        'locale': Platform.localeName,
        'timezone': DateTime.now().timeZoneName,
        'appVersion': kAppVersion,
        'packageName': 'com.aigent.studio',
      }, fromDevice: false);

  String _s(String k, [String fallback = '未知']) {
    final v = raw[k];
    if (v == null) return fallback;
    final t = v.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  int _i(String k) {
    final v = raw[k];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get manufacturer => _s('manufacturer');
  String get brand => _s('brand');
  String get model => _s('model');
  String get android => _s('android');
  String get hardware => _s('hardware', _s('board', '未知'));
  String get buildId => _s('buildId');
  String get locale => _s('locale');
  String get timezone => _s('timezone');
  String get appVersion => _s('appVersion', kAppVersion);
  String get packageName => _s('packageName', 'com.aigent.studio');
  int get sdk => _i('sdk');
  int get cpuCores => _i('cpuCores');
  int get totalMemMb => _i('totalMemMb');
  int get availMemMb => _i('availMemMb');
  int get width => _i('width');
  int get height => _i('height');
  int get density => _i('density');
  int get battery => _i('battery');
  int get storageTotalMb => _i('storageTotalMb');
  int get storageFreeMb => _i('storageFreeMb');

  List<String> get abis {
    final v = raw['abis'];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const <String>[];
  }

  String get displayName {
    final b = brand.toLowerCase();
    final m = model.toLowerCase();
    if (m.contains(b) && b.isNotEmpty) return model;
    return '$brand $model'.trim();
  }

  /// 注入 System Prompt 的紧凑摘要：让模型知道自己运行在什么设备上。
  String get promptSummary {
    final bits = <String>[
      '设备：$displayName（$manufacturer）',
      '系统：Android $android（API $sdk）',
      if (hardware != '未知') '芯片：$hardware',
      if (cpuCores > 0) '$cpuCores 核',
      if (abis.isNotEmpty) 'ABI ${abis.join('/')}',
      if (totalMemMb > 0) '内存 ${(totalMemMb / 1024).toStringAsFixed(1)} GB（可用 ${(availMemMb / 1024).toStringAsFixed(1)} GB）',
      if (width > 0) '屏幕 $width×$height @${density}dpi',
      if (storageTotalMb > 0) '存储 ${(storageTotalMb / 1024).toStringAsFixed(0)} GB（可用 ${(storageFreeMb / 1024).toStringAsFixed(0)} GB）',
      if (battery >= 0) '电量 $battery%',
      '地区 $locale / 时区 $timezone',
      '本应用 $appVersion（$packageName）',
    ];
    return bits.join('；');
  }

  /// 设置页用的逐行展示。
  List<({String label, String value})> get rows => [
        (label: '设备', value: displayName),
        (label: '厂商', value: manufacturer),
        (label: '系统', value: 'Android $android · API $sdk'),
        (label: '版本标识', value: buildId),
        (label: '芯片 / 核心', value: '$hardware · $cpuCores 核'),
        (label: '指令集', value: abis.isEmpty ? '未知' : abis.join(' / ')),
        (
          label: '运行内存',
          value: totalMemMb > 0
              ? '${(totalMemMb / 1024).toStringAsFixed(1)} GB · 可用 ${(availMemMb / 1024).toStringAsFixed(1)} GB'
              : '未知'
        ),
        (label: '屏幕', value: width > 0 ? '$width × $height · ${density}dpi' : '未知'),
        (
          label: '机身存储',
          value: storageTotalMb > 0
              ? '${(storageTotalMb / 1024).toStringAsFixed(0)} GB · 可用 ${(storageFreeMb / 1024).toStringAsFixed(0)} GB'
              : '未知'
        ),
        (label: '电量', value: battery >= 0 ? '$battery%' : '未知'),
        (label: '地区 / 时区', value: '$locale · $timezone'),
        (label: '应用版本', value: '$appVersion（$packageName）'),
        (label: '数据来源', value: fromDevice ? '本机系统接口' : '运行环境（非 Android）'),
      ];
}

/// 一个可从桌面启动的应用。
class InstalledApp {
  final String label;
  final String packageName;
  final bool system;

  const InstalledApp({
    required this.label,
    required this.packageName,
    this.system = false,
  });

  factory InstalledApp.fromJson(Map<dynamic, dynamic> j) => InstalledApp(
        label: (j['label'] ?? '').toString(),
        packageName: (j['package'] ?? '').toString(),
        system: j['system'] == true,
      );
}

/// 原生设备通道的 Dart 封装。
///
/// 关键约定：**任何调用都不允许把异常抛到上层的生成流程**。
/// 单元测试里没有原生通道（MissingPluginException），模拟器上也可能缺少某个
/// 系统 App；统一返回「失败结果」，由工具引擎转成一句人话回灌给模型。
class DeviceBridge {
  DeviceBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('aigent/device');

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, dynamic> args = const {}]) async {
    try {
      final r = await _channel.invokeMethod<T>(method, args);
      return r;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<DeviceInfo> info() async {
    final r = await _call<Map<dynamic, dynamic>>('device.info');
    if (r == null || r.isEmpty) return DeviceInfo.fallback();
    return DeviceInfo(Map<String, dynamic>.from(r));
  }

  Future<List<InstalledApp>> apps() async {
    final r = await _call<List<dynamic>>('device.apps');
    if (r == null) return const <InstalledApp>[];
    return r
        .whereType<Map<dynamic, dynamic>>()
        .map(InstalledApp.fromJson)
        .where((a) => a.packageName.isNotEmpty)
        .toList();
  }

  Future<bool> openApp(String package) =>
      _call<bool>('app.open', {'package': package}).then((v) => v == true);

  Future<bool> openUrl(String url) =>
      _call<bool>('web.open', {'url': url}).then((v) => v == true);

  Future<bool> addCalendar({
    required String title,
    required int startMillis,
    int? endMillis,
    String description = '',
    String location = '',
  }) =>
      _call<bool>('calendar.add', {
        'title': title,
        'start': startMillis,
        if (endMillis != null) 'end': endMillis,
        if (description.isNotEmpty) 'description': description,
        if (location.isNotEmpty) 'location': location,
      }).then((v) => v == true);

  Future<bool> setAlarm({
    required int hour,
    required int minute,
    String label = 'Aigent',
  }) =>
      _call<bool>('alarm.set', {
        'hour': hour,
        'minute': minute,
        'label': label,
      }).then((v) => v == true);

  Future<bool> shareText(String text, {String title = '分享'}) =>
      _call<bool>('share.text', {'text': text, 'title': title})
          .then((v) => v == true);

  Future<bool> setClipboard(String text) =>
      _call<bool>('clipboard.set', {'text': text}).then((v) => v == true);

  Future<bool> toast(String text) =>
      _call<bool>('toast', {'text': text}).then((v) => v == true);

  /// 应用专属外部目录下的工作区绝对路径；拿不到时返回 null，
  /// 由 [AgentWorkspace] 退回 `getApplicationDocumentsDirectory()`。
  Future<String?> workspaceRoot() => _call<String>('workspace.root');

  // -------------------------------------------------- v4.25 设备清理 / 找文件

  /// 只读：缓存、临时文件、工作区各自占多少，系统还剩多少空间。
  Future<StorageSummary?> storageSummary() async {
    final r = await _call<Map<dynamic, dynamic>>('storage.summary');
    if (r == null) return null;
    return StorageSummary.fromJson(Map<String, dynamic>.from(r));
  }

  /// 在**本应用可访问的目录**里按文件名找文件。
  /// Android 沙箱不允许遍历别的应用私有目录，这里不会假装做得到。
  Future<List<FoundFile>> searchFiles(String query, {int limit = 60}) async {
    final r = await _call<List<dynamic>>(
        'files.search', {'query': query, 'limit': limit});
    if (r == null) return const <FoundFile>[];
    return r
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => FoundFile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 清理本应用缓存、code_cache 与临时文件（不碰用户数据、不碰别的应用）。
  Future<CleanResult?> cleanCache() async {
    final r = await _call<Map<dynamic, dynamic>>('storage.clean');
    if (r == null) return null;
    return CleanResult.fromJson(Map<String, dynamic>.from(r));
  }

  /// 删除一个文件。原生侧会校验路径必须落在允许的根目录内，
  /// 越界一律拒绝，避免模型拼一个 `/sdcard/...` 就把别的东西删了。
  Future<bool> deleteFile(String path) =>
      _call<bool>('files.delete', {'path': path}).then((v) => v == true);

  /// 打开系统存储设置 / 本应用详情页。其它 App 的缓存只能由用户
  /// 或系统在这里清，第三方应用从 Android 7 起已无权代劳。
  Future<bool> openStorageSettings() =>
      _call<bool>('storage.openSettings').then((v) => v == true);
}

/// 存储占用快照，单位都是字节。
class StorageSummary {
  final int cacheBytes;
  final int tempBytes;
  final int workspaceBytes;
  final int freeBytes;
  final int totalBytes;
  final int cacheFiles;

  const StorageSummary({
    this.cacheBytes = 0,
    this.tempBytes = 0,
    this.workspaceBytes = 0,
    this.freeBytes = 0,
    this.totalBytes = 0,
    this.cacheFiles = 0,
  });

  int get reclaimable => cacheBytes + tempBytes;
  int get usedBytes => totalBytes - freeBytes;

  factory StorageSummary.fromJson(Map<dynamic, dynamic> j) => StorageSummary(
        cacheBytes: (j['cacheBytes'] as num?)?.toInt() ?? 0,
        tempBytes: (j['tempBytes'] as num?)?.toInt() ?? 0,
        workspaceBytes: (j['workspaceBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (j['freeBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        cacheFiles: (j['cacheFiles'] as num?)?.toInt() ?? 0,
      );

  /// 人话版大小：KB / MB / GB 两档小数。
  static String human(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class FoundFile {
  final String path;
  final String name;
  final int size;
  final int modified;
  final bool isDir;

  const FoundFile({
    required this.path,
    required this.name,
    this.size = 0,
    this.modified = 0,
    this.isDir = false,
  });

  factory FoundFile.fromJson(Map<dynamic, dynamic> j) => FoundFile(
        path: (j['path'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        modified: (j['modified'] as num?)?.toInt() ?? 0,
        isDir: j['isDir'] == true,
      );
}

class CleanResult {
  final int freedBytes;
  final int removedFiles;

  const CleanResult({this.freedBytes = 0, this.removedFiles = 0});

  factory CleanResult.fromJson(Map<dynamic, dynamic> j) => CleanResult(
        freedBytes: (j['freed'] as num?)?.toInt() ?? 0,
        removedFiles: (j['files'] as num?)?.toInt() ?? 0,
      );
}
