import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 端侧离线语音模型的下载与安装。
///
/// 为什么模型不塞进 APK：中文小模型解压后约 90 MB，直接打包会让安装包
/// 翻三倍，而多数人根本不用语音。这里改成「首次点麦克风时下载一次」，
/// 之后识别全程不联网，也不再产生任何流量。
///
/// 存放位置是应用私有目录（`files/speech/`），卸载即清理，不会出现在
/// 相册或下载目录里。
class SpeechModelStatus {
  final bool ready;

  /// 已安装模型占用的字节数；未安装为 0。
  final int bytes;

  /// 模型根目录（传给原生 `Model(path)` 的路径）。
  final String path;

  const SpeechModelStatus({
    required this.ready,
    this.bytes = 0,
    this.path = '',
  });

  static const SpeechModelStatus missing =
      SpeechModelStatus(ready: false, bytes: 0, path: '');

  String get sizeLabel {
    if (bytes <= 0) return '未下载';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class SpeechModel {
  SpeechModel._();

  /// 与 [sttEngineById] 里的 id 保持一致。
  static const String engineId = 'vosk-cn';

  /// Vosk 官方中文小模型：约 42 MB 压缩包，解压约 90 MB。
  /// 选小模型而不是 1.3 GB 的大模型，是因为手机上首字延迟更重要；
  /// 大模型在低端机上加载就要好几秒。
  static const String dirName = 'vosk-model-small-cn-0.22';

  /// 随 APK 一起分发的压缩包。
  ///
  /// 之前只给一个境外下载地址，结果在手机上根本下不动——用户看到的
  /// 是「点了没反应 / 一直 0%」。现在模型直接打进安装包，首次使用
  /// 从本地解压，不需要任何网络。
  static const String assetZip = 'assets/speech/vosk-model-small-cn-0.22.zip';

  static const String downloadUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip';
  static const int downloadBytes = 43898754;

  /// 兜底下载源，按可用性排序：国内镜像优先，官方源最后。
  /// 每个源失败都会自动换下一个，不再让一次 DNS 超时毁掉整个安装。
  static const List<SpeechSource> sources = [
    SpeechSource(
      '国内镜像',
      'https://hf-mirror.com/xushunbin/vosk-model-cn-kaldi-multicn-0.15/resolve/main/vosk-model-small-cn-0.22.zip',
    ),
    SpeechSource(
      '官方源',
      'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip',
    ),
  ];

  static Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'speech'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<Directory> modelDir() async {
    final root = await _root();
    return Directory(p.join(root.path, dirName));
  }

  static Future<bool> _valid(Directory dir) async {
    // Vosk 只认 am/final.mdl + graph；少一个文件就加载失败，这里先挡掉。
    final mdl = File(p.join(dir.path, 'am', 'final.mdl'));
    final graph = Directory(p.join(dir.path, 'graph'));
    return mdl.existsSync() && graph.existsSync();
  }

  static Future<SpeechModelStatus> status() async {
    try {
      final dir = await modelDir();
      if (!await _valid(dir)) return SpeechModelStatus.missing;
      var total = 0;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
      return SpeechModelStatus(ready: true, bytes: total, path: dir.path);
    } catch (_) {
      return SpeechModelStatus.missing;
    }
  }

  /// 安装语音包：先解压随包分发的资源，失败再走网络多源。
  ///
  /// 失败会清掉半成品，不会留下一个「看起来装好了」的空目录。
  static Future<SpeechModelStatus> download({
    void Function(double progress, int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final root = await _root();
    final zip = File(p.join(root.path, '$dirName.zip'));

    // 1) 内置资源：不联网，绝大多数用户走这条。
    try {
      final done = await _fromAsset(zip, onProgress: onProgress);
      if (done) return status();
    } catch (_) {
      // 资源缺失（精简构建）或磁盘不足：继续试网络源。
    }

    // 2) 网络多源。
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
    ));
    Object? last;
    for (final src in sources) {
      if (cancelToken?.isCancelled ?? false) break;
      try {
        await dio.download(
          src.url,
          zip.path,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            final t = total > 0 ? total : downloadBytes;
            onProgress?.call(
              (received / t).clamp(0.0, 1.0).toDouble(),
              received,
              t,
            );
          },
        );
        if (!await zip.exists() || await zip.length() < 1024 * 1024) {
          throw const SpeechModelException('下载不完整');
        }
        if (await _unpack(zip)) return status();
      } catch (e) {
        last = e;
        try {
          if (await zip.exists()) await zip.delete();
        } catch (_) {}
      }
    }
    if (cancelToken?.isCancelled ?? false) {
      throw const SpeechModelException('已取消下载');
    }
    throw SpeechModelException(
      last == null ? '语音包安装失败，请重试' : '语音包下载失败：${_short(last)}',
    );
  }

  /// 从 assets 读取压缩包 → 落盘 → 解压。成功返回 true。
  static Future<bool> _fromAsset(
    File zip, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final data = await rootBundle.load(assetZip);
    final total = data.lengthInBytes;
    if (total < 1024 * 1024) return false;

    final sink = zip.openWrite();
    // 分块写：一次 write 43 MB 会让低端机在解压前就先卡一下。
    const chunk = 4 << 20;
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    var written = 0;
    while (written < total) {
      final end = (written + chunk).clamp(0, total);
      sink.add(bytes.sublist(written, end));
      written = end;
      // 落盘占进度前 40%，解压占后 60%，进度条不会停在 99% 假死。
      onProgress?.call((written / total) * 0.4, written, total);
    }
    await sink.flush();
    await sink.close();
    return _unpack(zip);
  }

  /// 解压到临时目录，校验通过后原子替换到正式位置。
  static Future<bool> _unpack(File zip) async {
    final root = await _root();
    final tmp = Directory(p.join(root.path, '${dirName}_tmp'));
    final target = Directory(p.join(root.path, dirName));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    try {
      final zipPath = zip.path;
      final outPath = tmp.path;
      // 解压是纯 CPU 操作，放 isolate 里跑，避免界面卡几百毫秒。
      await Isolate.run(() => extractFileToDisk(zipPath, outPath));

      // zip 里自带一层 dirName 目录，统一挪到正式位置。
      var source = Directory(p.join(tmp.path, dirName));
      if (!await source.exists()) source = tmp;
      if (!await _valid(source)) {
        throw const SpeechModelException('语音包校验失败');
      }
      if (await target.exists()) await target.delete(recursive: true);
      await source.rename(target.path);
      try {
        if (await zip.exists()) await zip.delete();
      } catch (_) {}
      return true;
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      } catch (_) {}
      try {
        if (await zip.exists()) await zip.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> remove() async {
    final root = await _root();
    final dir = Directory(p.join(root.path, dirName));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }
}

class SpeechModelException implements Exception {
  final String message;
  const SpeechModelException(this.message);
  @override
  String toString() => message;
}

class SpeechSource {
  final String label;
  final String url;
  const SpeechSource(this.label, this.url);
}
