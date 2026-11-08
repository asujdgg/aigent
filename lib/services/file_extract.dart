import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';

/// 图片发送前的诊断结果（只读，供设置页展示）。
class ImageDiag {
  final String name;
  final String mime;
  final int bytes;
  final int base64Len;
  final bool supported;
  final String? note;

  const ImageDiag({
    required this.name,
    required this.mime,
    required this.bytes,
    required this.base64Len,
    required this.supported,
    this.note,
  });

  String get sizeLabel => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

const Set<String> kImageExt = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
  'heic'
};

const Set<String> kTextExt = {
  'txt',
  'md',
  'markdown',
  'csv',
  'tsv',
  'json',
  'jsonl',
  'yaml',
  'yml',
  'xml',
  'html',
  'htm',
  'log',
  'ini',
  'conf',
  'toml',
  'sql',
  'py',
  'js',
  'ts',
  'dart',
  'java',
  'kt',
  'go',
  'rs',
  'c',
  'h',
  'cpp',
  'cs',
  'sh',
  'bat',
  'swift',
  'rb',
  'php',
  'css',
  'scss',
  'tex',
  'srt',
  'vtt'
};

/// 本地文本抽取：图片原样送视觉模型；PDF 走文本层抽取；文本类直接解码。
class FileExtractService {
  static const int _maxChars = 60000;

  static String ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static Future<Attachment> fromPlatformFile(PlatformFile f) async {
    Uint8List bytes = f.bytes ?? Uint8List(0);
    if (bytes.isEmpty && f.path != null) {
      try {
        bytes = await File(f.path!).readAsBytes();
      } catch (_) {}
    }
    final name = f.name;
    final e = ext(name);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${f.size}';

    if (kImageExt.contains(e)) {
      return Attachment(
        id: id,
        name: name,
        kind: AttachKind.image,
        size: bytes.length,
        imageBytes: bytes,
        imageMime: imageMimeOf(bytes),
      );
    }

    if (e == 'pdf') {
      final text = extractPdf(bytes);
      return Attachment(
        id: id,
        name: name,
        kind: AttachKind.pdf,
        size: bytes.length,
        text: _cap(text.isEmpty ? '（未能从该 PDF 提取到文本层，可能为扫描件）' : text),
      );
    }

    if (kTextExt.contains(e) || _looksText(bytes)) {
      return Attachment(
        id: id,
        name: name,
        kind: AttachKind.text,
        size: bytes.length,
        text: _cap(_decode(bytes)),
      );
    }

    return Attachment(
      id: id,
      name: name,
      kind: AttachKind.text,
      size: bytes.length,
      text: '（二进制文件 $name 无法提取文本，请转换为 TXT / CSV / PDF 后重试）',
    );
  }

  static Future<Attachment> fromXFile(XFile f) async {
    final bytes = await f.readAsBytes();
    final name = f.name.isEmpty
        ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
        : f.name;
    return Attachment(
      id: '${DateTime.now().microsecondsSinceEpoch}_${bytes.length}',
      name: name,
      kind: AttachKind.image,
      size: bytes.length,
      imageBytes: bytes,
      imageMime: imageMimeOf(bytes),
    );
  }

  /// 按文件头魔数判定真实图片格式。压缩、重命名、相册临时名都会让扩展名失真，
  /// 误把 HEIC / BMP 声明成 image/jpeg 是「图片发出去却解不开」的常见原因。
  static String? imageMimeOf(Uint8List b) {
    if (b.length < 12) return null;
    bool eq(int off, List<int> sig) {
      if (off + sig.length > b.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[off + i] != sig[i]) return false;
      }
      return true;
    }

    if (eq(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (eq(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (eq(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (eq(0, [0x52, 0x49, 0x46, 0x46]) && eq(8, [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }
    if (eq(0, [0x42, 0x4D])) return 'image/bmp';
    if (eq(0, [0x49, 0x49, 0x2A, 0x00]) || eq(0, [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'image/tiff';
    }
    if (eq(4, [0x66, 0x74, 0x79, 0x70])) {
      final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
      if (brand.contains('avif')) return 'image/avif';
      if (brand.contains('heic') ||
          brand.contains('heix') ||
          brand.contains('hevc') ||
          brand.contains('mif1') ||
          brand.contains('msf1')) {
        return 'image/heic';
      }
    }
    return null;
  }

  /// 主流视觉模型普遍接受的格式。其他格式即使发出去也多半解不开。
  static const Set<String> kVisionSafeMime = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  static String _cap(String s) {
    if (s.length <= _maxChars) return s;
    return '${s.substring(0, _maxChars)}\n\n（文本已截断至 $_maxChars 字符）';
  }

  static bool _looksText(Uint8List b) {
    if (b.isEmpty) return false;
    final n = b.length > 2048 ? 2048 : b.length;
    var bad = 0;
    for (var i = 0; i < n; i++) {
      final c = b[i];
      if (c == 0) return false;
      if (c < 7 || (c > 13 && c < 32)) bad++;
    }
    return bad < n * 0.02;
  }

  static String _decode(Uint8List b) {
    try {
      return utf8.decode(b);
    } catch (_) {
      return latin1.decode(b, allowInvalid: true);
    }
  }

  /// PDF 主路径：Syncfusion 文本抽取；失败时回退到纯 Dart 的 FlateDecode + 文本操作符解析。
  static String extractPdf(Uint8List bytes) {
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(doc).extractText();
      doc.dispose();
      if (text.trim().isNotEmpty) return text.trim();
    } catch (_) {}
    return _extractPdfFallback(bytes);
  }

  static String _extractPdfFallback(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final out = StringBuffer();
    final streamRe = RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream');
    for (final m in streamRe.allMatches(raw)) {
      final seg = m.group(1);
      if (seg == null || seg.isEmpty) continue;
      List<int> data = latin1.encode(seg);
      try {
        data = const ZLibDecoder().decodeBytes(data);
      } catch (_) {}
      final content = latin1.decode(data, allowInvalid: true);
      if (!content.contains('BT') &&
          !content.contains('Tj') &&
          !content.contains('TJ')) {
        continue;
      }
      out.write(_operators(content));
      out.write('\n');
    }
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  static String _operators(String s) {
    final b = StringBuffer();
    final re = RegExp(r'\((?:\\.|[^\\()])*\)');
    for (final m in re.allMatches(s)) {
      final g = m.group(0)!;
      var t = g.substring(1, g.length - 1);
      t = t.replaceAllMapped(RegExp(r'\\([nrtbf()\\])'), (mm) {
        switch (mm.group(1)) {
          case 'n':
            return '\n';
          case 'r':
            return '\r';
          case 't':
            return '\t';
          default:
            return mm.group(1)!;
        }
      });
      t = t.replaceAll(RegExp(r'\\[0-7]{1,3}'), ' ');
      if (t.trim().isNotEmpty) {
        b.write(t);
        b.write(' ');
      }
    }
    return b.toString();
  }

  /// 单张图片的发送前诊断信息，用于「为什么识别不了」的自查。
  static List<ImageDiag> diagnose(List<Attachment> list) {
    final out = <ImageDiag>[];
    for (final a in list) {
      if (!a.isImage) continue;
      final mime = a.mime;
      final bytes = a.imageBytes!.length;
      final safe = kVisionSafeMime.contains(mime);
      String? note;
      if (!safe) {
        note = '多数视觉模型不接受 $mime，请转成 JPG / PNG 后重试';
      } else if (bytes > 4 * 1024 * 1024) {
        note = '单图超过 4 MB，部分网关会以 HTTP 413 拒绝，建议压缩后重试';
      }
      out.add(ImageDiag(
        name: a.name,
        mime: mime,
        bytes: bytes,
        base64Len: ((bytes + 2) ~/ 3) * 4,
        supported: safe,
        note: note,
      ));
    }
    return out;
  }

  /// 生成一条带图的 user 消息。无图片时返回 null，调用方走纯文本路径。
  ///
  /// [fmt] 决定图片的编码方式：不同网关对多模态的支持差异极大，
  /// 标准 OpenAI 格式并非通用，所以允许切换以排查「发出去却识别不了」。
  static Map<String, dynamic>? imageMessage(
      String text, List<Attachment> list, VisionFormat fmt) {
    final imgs = list.where((a) => a.isImage).toList();
    if (imgs.isEmpty) return null;
    final t = text.trim().isEmpty ? '请分析这些图片。' : text;

    if (fmt == VisionFormat.textOnly) {
      final b = StringBuffer(t);
      b.writeln();
      b.writeln('[当前为「仅文本」模式，以下图片未发送给模型]');
      for (final a in imgs) {
        b.writeln('- ${a.name} · ${a.sizeLabel} · ${a.mime}');
      }
      return {'role': 'user', 'content': b.toString()};
    }

    if (fmt == VisionFormat.ollama) {
      return {
        'role': 'user',
        'content': t,
        // Ollama 及其部分兼容层用顶层 images 数组，且只要纯 base64。
        'images': [for (final a in imgs) base64Encode(a.imageBytes!)],
      };
    }

    final parts = <Map<String, dynamic>>[
      {'type': 'text', 'text': t},
    ];
    for (final a in imgs) {
      final b64 = base64Encode(a.imageBytes!);
      final url = <String, dynamic>{'url': 'data:${a.mime};base64,$b64'};
      if (fmt == VisionFormat.openai) url['detail'] = 'auto';
      parts.add({'type': 'image_url', 'image_url': url});
    }
    return {'role': 'user', 'content': parts};
  }

  /// 文本文件 / PDF 抽取结果拼成上下文文本。
  static String textContext(List<Attachment> list) {
    if (list.isEmpty) return '';
    final b = StringBuffer();
    b.writeln('[用户附加的文件内容]');
    for (final a in list) {
      if (a.isImage || a.text == null || a.text!.trim().isEmpty) continue;
      b.writeln('--- 文件: ${a.name} (${a.sizeLabel}) ---');
      b.writeln(a.text);
      b.writeln('--- 文件结束 ---');
    }
    return b.toString();
  }
}
