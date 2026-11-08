import 'dart:convert';

import 'package:dio/dio.dart';

/// 一条 GitHub 仓库搜索结果。
class RepoResult {
  final String fullName;
  final String description;
  final String url;
  final String language;
  final int stars;
  final String pushedAt;
  final bool archived;

  const RepoResult({
    required this.fullName,
    required this.description,
    required this.url,
    this.language = '',
    this.stars = 0,
    this.pushedAt = '',
    this.archived = false,
  });

  /// 列表里用的一行元信息：star · 语言 · 最近更新。
  String get metaLine {
    final bits = <String>[];
    if (stars > 0) bits.add(_stars(stars));
    if (language.isNotEmpty) bits.add(language);
    if (pushedAt.length >= 10) bits.add(pushedAt.substring(0, 10));
    if (archived) bits.add('已归档');
    return bits.join(' · ');
  }

  static String _stars(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k stars';
    }
    return '$n stars';
  }
}

class ProjectSearchException implements Exception {
  final String message;
  const ProjectSearchException(this.message);
  @override
  String toString() => message;
}

/// 全网搜索开源项目。
///
/// 内置目录只能覆盖「我知道的」项目，用户要的是「全部」。这里直接查
/// GitHub 仓库搜索，按 star 排序，能翻到目录里没有的新实现。
/// 不登录也能用，代价是接口按 IP 限流（每分钟十次左右）。
class ProjectSearch {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
    followRedirects: true,
    headers: const {'Accept': 'application/vnd.github+json'},
  ));

  /// 首页给的快捷词，覆盖三类需求：网页版反代、免密、公益站。
  static const List<String> quickQueries = [
    '2api',
    'free-api',
    'chatgpt 反代',
    '公益 API',
  ];

  static Future<List<RepoResult>> search(String query, {int limit = 15}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https('api.github.com', '/search/repositories', {
      'q': q,
      'sort': 'stars',
      'order': 'desc',
      'per_page': '$limit',
    });
    try {
      final resp = await _dio.get<String>(uri.toString());
      final code = resp.statusCode ?? 0;
      if (code == 403 || code == 429) {
        throw const ProjectSearchException('GitHub 限流了，等一分钟再搜，或先用内置目录');
      }
      if (code != 200) {
        throw ProjectSearchException('搜索失败（HTTP $code）');
      }
      return parse(resp.data);
    } on ProjectSearchException {
      rethrow;
    } on DioException {
      throw const ProjectSearchException('连不上 GitHub，检查网络后再试');
    }
  }

  /// 解析 GitHub 的返回体。[data] 允许是 JSON 字符串或已解码的对象。
  static List<RepoResult> parse(dynamic data) {
    dynamic v = data;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    if (v is! Map) return const [];
    final items = v['items'];
    if (items is! List) return const [];
    final out = <RepoResult>[];
    for (final e in items) {
      if (e is! Map) continue;
      final name = (e['full_name'] ?? '').toString();
      if (name.isEmpty) continue;
      out.add(RepoResult(
        fullName: name,
        description: (e['description'] ?? '').toString(),
        url: (e['html_url'] ?? 'https://github.com/$name').toString(),
        language: (e['language'] ?? '').toString(),
        stars: (e['stargazers_count'] as num?)?.toInt() ?? 0,
        pushedAt: (e['pushed_at'] ?? '').toString(),
        archived: e['archived'] == true,
      ));
    }
    return out;
  }
}
