import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../theme.dart';

/// 源码文件（构建期从工程目录打包进 assets，离线可读）。
class SourceFile {
  final String path;
  final int lines;
  final int size;
  final String content;

  const SourceFile({
    required this.path,
    required this.lines,
    required this.size,
    required this.content,
  });

  factory SourceFile.fromJson(Map<dynamic, dynamic> j) => SourceFile(
        path: (j['path'] ?? '').toString(),
        lines: (j['lines'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        content: (j['content'] ?? '').toString(),
      );
}

class SourceBundle {
  final String version;
  final String build;
  final String generated;
  final int fileCount;
  final int totalLines;
  final List<SourceFile> files;

  const SourceBundle({
    required this.version,
    required this.build,
    required this.generated,
    required this.fileCount,
    required this.totalLines,
    required this.files,
  });

  static SourceBundle parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final raw = (j['files'] as List<dynamic>? ?? const []);
    return SourceBundle(
      version: (j['version'] ?? '').toString(),
      build: (j['build'] ?? '').toString(),
      generated: (j['generated'] ?? '').toString(),
      fileCount: (j['fileCount'] as num?)?.toInt() ?? raw.length,
      totalLines: (j['totalLines'] as num?)?.toInt() ?? 0,
      files: raw
          .whereType<Map<dynamic, dynamic>>()
          .map(SourceFile.fromJson)
          .where((f) => f.path.isNotEmpty)
          .toList(),
    );
  }
}

/// 关于 → 查看源代码。
///
/// 源码在构建时由 `tool/build_source_assets.py` 打进 assets，完全离线，
/// 不需要网络、不需要外部浏览器，也不会读取设备上的其它文件。
class SourceBrowser extends StatefulWidget {
  const SourceBrowser({super.key});

  @override
  State<SourceBrowser> createState() => _SourceBrowserState();
}

class _SourceBrowserState extends State<SourceBrowser> {
  late Future<SourceBundle> _future;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _search.addListener(() {
      if (mounted) setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static Future<SourceBundle> _load() async {
    final text = await rootBundle.loadString('assets/source_bundle.json');
    return SourceBundle.parse(text);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: AppBar(
        backgroundColor: canvasOf(dark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(t('源代码'), style: ts(dark, size: 16, weight: FontWeight.w600)),
        iconTheme: IconThemeData(color: dark ? C.dInk : C.ink),
      ),
      body: FutureBuilder<SourceBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('源码资源未能加载：${snap.error}',
                    style: meta(dark, size: 11.5, height: 1.6)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final bundle = snap.data!;
          final list = _query.isEmpty
              ? bundle.files
              : bundle.files
                  .where((f) => f.path.toLowerCase().contains(_query))
                  .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Text(
                  'v${bundle.version}${bundle.build.isEmpty ? '' : '+${bundle.build}'}'
                  ' · ${bundle.fileCount} 个文件 · '
                  '${bundle.totalLines} 行 · 打包于 ${bundle.generated}',
                  style: meta(dark,
                      size: 12,
                      height: 1.6,
                      color: dark ? C.dInk2 : C.ink2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _search,
                  style: ts(dark, size: 13),
                  decoration: fieldDecoration(dark, hint: t('按路径筛选，如 app_state / AndroidManifest')),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      Container(height: 1, color: hairOf(dark)),
                  itemBuilder: (_, i) {
                    final f = list[i];
                    return InkWell(
                      onTap: () => Navigator.of(context).push(
                        SoftPageRoute<void>(
                          builder: (_) => SourceFileView(file: f),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.insert_drive_file_outlined,
                                size: 15, color: dark ? C.dInk3 : C.ink3),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(f.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ts(dark, size: 13)),
                            ),
                            const SizedBox(width: 10),
                            Text('${f.lines} 行',
                                style: meta(dark, size: 11.5)),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded,
                                size: 16, color: dark ? C.dInk3 : C.ink3),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SourceFileView extends StatelessWidget {
  final SourceFile file;
  const SourceFileView({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 超大文件只渲染前 12000 字，避免一次性布局几千行拖慢滚动；
    // 「复制全文」拿到的始终是完整内容。
    const int limit = 12000;
    final clipped = file.content.length > limit;
    final shown = clipped
        ? '${file.content.substring(0, limit)}\n\n…（共 ${file.content.length} 字，'
            '此处只显示前 $limit 字，点右上角可复制全文）'
        : file.content;
    return Scaffold(
      backgroundColor: canvasOf(dark),
      appBar: AppBar(
        backgroundColor: canvasOf(dark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(file.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(dark, size: 13)),
        iconTheme: IconThemeData(color: dark ? C.dInk : C.ink),
        actions: [
          IconButton(
            tooltip: t('复制全文'),
            icon: Icon(Icons.copy_all_outlined,
                size: 19, color: dark ? C.dInk2 : C.ink2),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: file.content));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(t('源码已复制')), duration: const Duration(seconds: 1)),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: SelectableText(
          shown,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.55,
            color: dark ? C.dInk2 : C.ink2,
          ),
        ),
      ),
    );
  }
}
