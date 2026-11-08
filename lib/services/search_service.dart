import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/models.dart';

class SearchHit {
  final String title;
  final String url;
  final String snippet;
  final String source;

  const SearchHit({
    required this.title,
    required this.url,
    this.snippet = '',
    this.source = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
        'source': source,
      };

  factory SearchHit.fromJson(Map<dynamic, dynamic> j) => SearchHit(
        title: (j['title'] ?? j['name'] ?? '').toString(),
        url: (j['url'] ?? j['link'] ?? '').toString(),
        snippet:
            (j['snippet'] ?? j['content'] ?? j['description'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
      );
}

/// 一次搜索的请求描述。所有内置源都归一成它，解析统一走 [_extract]。
class _Spec {
  final String url;
  final bool post;
  final Map<String, dynamic> query;
  final Map<String, dynamic> body;
  final Map<String, String> headers;

  const _Spec(
    this.url, {
    this.post = false,
    this.query = const {},
    this.body = const {},
    this.headers = const {},
  });
}

/// 联网检索：支持同时启用多个搜索源，并行请求、按 URL 去重后交错合并。
/// 响应解析采用启发式遍历，能兼容各服务商不同层级的字段名与嵌套结构。
class SearchService {
  SearchService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
          followRedirects: true,
        ));

  final Dio _dio;

  /// 主入口：所有已启用源并行检索，任一源失败不影响其他源。
  /// [cancel] 让「停止」按钮在检索阶段就能立即中断请求；即使个别源挂起，
  /// 总超时也会兜底返回，状态栏不会永远停在「联网检索中」。
  Future<List<SearchHit>> search(
    String query,
    AppSettings cfg, {
    CancelToken? cancel,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (!cfg.searchActive) return const [];
    final sources = cfg.activeSources;
    final n = cfg.searchCount.clamp(1, 20);
    final cap = (n * 2).clamp(n, 40);

    final batches = await Future.wait<List<SearchHit>>(
      sources.map((p) async {
        try {
          return await _searchOne(q, p, cfg, n, cancel: cancel);
        } catch (_) {
          return <SearchHit>[];
        }
      }),
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => <List<SearchHit>>[],
    );

    // 交错取每个源的第 1、2、3… 条，避免第一个源占满全部引用位。
    final out = <SearchHit>[];
    final seen = <String>{};
    var idx = 0;
    while (out.length < cap) {
      var progressed = false;
      for (final list in batches) {
        if (idx >= list.length) continue;
        progressed = true;
        if (out.length >= cap) break;
        final h = list[idx];
        if (seen.add(h.url)) out.add(h);
      }
      if (!progressed) break;
      idx++;
    }
    return out;
  }

  /// 设置页「测试已启用搜索源」：逐源报告结果数或失败原因。
  Future<Map<SearchProvider, String>> testAll(
      String query, AppSettings cfg) async {
    final n = cfg.searchCount.clamp(1, 20);
    final out = <SearchProvider, String>{};
    await Future.wait(cfg.activeSources.map((p) async {
      try {
        final hits = await _searchOne(query.trim(), p, cfg, n);
        out[p] = '${hits.length} 条结果';
      } catch (e) {
        final msg = e.toString().replaceAll('StateError: ', '');
        out[p] = '失败 · ${msg.length > 46 ? '${msg.substring(0, 46)}…' : msg}';
      }
    }));
    return out;
  }

  Future<List<SearchHit>> _searchOne(
      String q, SearchProvider p, AppSettings cfg, int n,
      {CancelToken? cancel}) async {
    final key = cfg.sourceKey(p).trim();
    var ep = cfg.sourceEndpoint(p).trim();
    if (ep.isEmpty) ep = p.endpoint;

    // Jina 返回 Markdown 文本而非 JSON，单独走文本解析。
    if (p == SearchProvider.jina) {
      return _jina(q, ep, key, n, p.shortLabel, cancel: cancel);
    }
    if (ep.isEmpty) throw StateError('请在设置里填写 ${p.label} 的接口地址');

    final spec = _build(p, q, ep, key, n, cfg.sourceCx(p).trim());
    final resp = await _send(spec, p.label, cancel: cancel);
    if (p == SearchProvider.wikipedia) {
      return _wiki(resp.data, ep, n, p.shortLabel);
    }
    if (p == SearchProvider.githubRepo ||
        p == SearchProvider.githubCode ||
        p == SearchProvider.githubIssues) {
      return _github(resp.data, p, n);
    }
    return _extract(resp.data, limit: n, source: p.shortLabel);
  }

  _Spec _build(
      SearchProvider p, String q, String ep, String key, int n, String cx) {
    final bearer = <String, String>{
      if (key.isNotEmpty) 'Authorization': 'Bearer $key'
    };
    switch (p) {
      case SearchProvider.tavily:
        return _Spec(
          ep,
          post: true,
          headers: bearer,
          body: {
            'api_key': key,
            'query': q,
            'max_results': n,
            'search_depth': 'basic',
            'include_answer': false,
            'topic': 'general',
          },
        );
      case SearchProvider.serper:
        return _Spec(
          ep,
          post: true,
          headers: {if (key.isNotEmpty) 'X-API-KEY': key},
          body: {'q': q, 'num': n, 'gl': 'cn', 'hl': 'zh-cn'},
        );
      case SearchProvider.serpapi:
        return _Spec(ep, query: {
          'engine': 'google',
          'q': q,
          'num': n,
          'api_key': key,
          'hl': 'zh-cn',
        });
      case SearchProvider.searchapi:
        return _Spec(ep, query: {
          'engine': 'google',
          'q': q,
          'num': n,
          'api_key': key,
          'gl': 'cn',
          'hl': 'zh-cn',
        });
      case SearchProvider.brave:
        return _Spec(
          ep,
          headers: {'X-Subscription-Token': key, 'Accept': 'application/json'},
          query: {'q': q, 'count': n, 'search_lang': 'zh'},
        );
      case SearchProvider.exa:
        return _Spec(
          ep,
          post: true,
          headers: {if (key.isNotEmpty) 'x-api-key': key},
          body: {
            'query': q,
            'numResults': n,
            'type': 'auto',
            'contents': {
              'text': {'maxCharacters': 700}
            },
          },
        );
      case SearchProvider.you:
        return _Spec(
          ep,
          headers: {if (key.isNotEmpty) 'X-API-Key': key},
          query: {'query': q, 'num_web_results': n},
        );
      case SearchProvider.firecrawl:
        return _Spec(
          ep,
          post: true,
          headers: bearer,
          body: {
            'query': q,
            'limit': n,
            'scrapeOptions': {
              'formats': ['markdown']
            },
          },
        );
      case SearchProvider.bing:
        return _Spec(
          ep,
          headers: {if (key.isNotEmpty) 'Ocp-Apim-Subscription-Key': key},
          query: {
            'q': q,
            'count': n,
            'responseFilter': 'Webpages',
            'setLang': 'zh-CN'
          },
        );
      case SearchProvider.google:
        return _Spec(ep, query: {
          'key': key,
          'cx': cx,
          'q': q,
          'num': n.clamp(1, 10),
          'hl': 'zh-CN',
        });
      case SearchProvider.bocha:
        return _Spec(
          ep,
          post: true,
          headers: bearer,
          body: {
            'query': q,
            'count': n,
            'freshness': 'noLimit',
            'summary': true
          },
        );
      case SearchProvider.githubRepo:
        return _Spec(
          ep,
          headers: _ghHeaders(key),
          query: {'q': q, 'per_page': n, 'sort': 'stars'},
        );
      case SearchProvider.githubCode:
        return _Spec(ep,
            headers: _ghHeaders(key), query: {'q': q, 'per_page': n});
      case SearchProvider.githubIssues:
        return _Spec(
          ep,
          headers: _ghHeaders(key),
          query: {'q': q, 'per_page': n, 'sort': 'updated'},
        );
      case SearchProvider.searxng:
        var u = ep;
        if (!u.contains('/search')) {
          u = '${u.replaceAll(RegExp(r'/+$'), '')}/search';
        }
        return _Spec(
          u,
          headers: key.isEmpty ? const {} : {'Authorization': 'Bearer $key'},
          query: {
            'q': q,
            'format': 'json',
            'language': 'zh-CN',
            'safesearch': 0
          },
        );
      case SearchProvider.ddg:
        return _Spec(ep, query: {
          'q': q,
          'format': 'json',
          'no_html': 1,
          'skip_disambig': 1,
          'no_redirect': 1,
        });
      case SearchProvider.wikipedia:
        return _Spec(ep, query: {
          'action': 'query',
          'list': 'search',
          'srsearch': q,
          'srlimit': n,
          'format': 'json',
          'utf8': 1,
          'origin': '*',
        });
      case SearchProvider.mojeek:
        return _Spec(ep, query: {'q': q, 'fmt': 'json', 't': n, 'k': key});
      case SearchProvider.yep:
        return _Spec(ep, query: {
          'client': 'web',
          'gl': 'CN',
          'limit': n,
          'no_correct': 'false',
          'q': q,
          'safeSearch': 'off',
          'type': 'web',
        });
      case SearchProvider.custom:
        final url = ep
            .replaceAll('{query}', Uri.encodeQueryComponent(q))
            .replaceAll('{q}', Uri.encodeQueryComponent(q))
            .replaceAll('{count}', '$n');
        return _Spec(url, headers: bearer);
      case SearchProvider.jina:
        throw StateError('unreachable');
    }
  }

  static Map<String, String> _ghHeaders(String key) => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Aigent-App',
        if (key.isNotEmpty) 'Authorization': 'Bearer $key',
      };

  Future<Response<dynamic>> _send(_Spec s, String name,
      {CancelToken? cancel}) async {
    final opts = Options(
      contentType: Headers.jsonContentType,
      headers: {'Accept': 'application/json', ...s.headers},
      validateStatus: (_) => true,
    );
    final Response<dynamic> r;
    try {
      if (s.post) {
        r = await _dio.post<dynamic>(
          s.url,
          data: s.body.isEmpty ? null : jsonEncode(s.body),
          queryParameters: s.query.isEmpty ? null : s.query,
          options: opts,
          cancelToken: cancel,
        );
      } else {
        r = await _dio.get<dynamic>(
          s.url,
          queryParameters: s.query.isEmpty ? null : s.query,
          options: opts,
          cancelToken: cancel,
        );
      }
    } on DioException catch (e) {
      throw StateError('$name 请求失败：${e.message ?? e.type.name}');
    }
    final c = r.statusCode ?? 0;
    if (c < 200 || c >= 300) {
      final detail = _short(r.data);
      if (c == 401 || c == 403) {
        throw StateError('$name HTTP $c · 密钥无效或配额不足 $detail');
      }
      throw StateError('$name 返回 HTTP $c · $detail');
    }
    return r;
  }

  Future<List<SearchHit>> _jina(
      String q, String ep, String key, int n, String source,
      {CancelToken? cancel}) async {
    final base = ep.endsWith('/') ? ep : '$ep/';
    final url = '$base${Uri.encodeComponent(q)}';
    final Response<dynamic> r;
    try {
      r = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: {
            'Accept': 'text/plain',
            'X-Return-Format': 'markdown',
            if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
          validateStatus: (_) => true,
        ),
        cancelToken: cancel,
      );
    } on DioException catch (e) {
      throw StateError('Jina 请求失败：${e.message ?? e.type.name}');
    }
    if ((r.statusCode ?? 0) < 200 || (r.statusCode ?? 0) >= 300) {
      throw StateError('Jina 返回 HTTP ${r.statusCode} · ${_short(r.data)}');
    }
    final text = r.data == null ? '' : r.data.toString();
    if (text.trim().isEmpty) return const [];
    return _fromText(text, n, source);
  }

  static List<SearchHit> _wiki(dynamic data, String ep, int n, String source) {
    final root = _asMap(data);
    final query = root['query'];
    final list = query is Map ? query['search'] : null;
    if (list is! List) return _extract(data, limit: n, source: source);
    final uri = Uri.tryParse(ep);
    final origin = uri != null && uri.hasScheme
        ? '${uri.scheme}://${uri.host}'
        : 'https://zh.wikipedia.org';
    final out = <SearchHit>[];
    for (final e in list) {
      if (e is! Map || out.length >= n) continue;
      final title = (e['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(SearchHit(
        title: title,
        url: '$origin/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
        snippet: _clean((e['snippet'] ?? '').toString()),
        source: source,
      ));
    }
    return out;
  }

  /// GitHub Search API：items[] 里的 html_url / full_name / path / title 需要专门映射。
  static List<SearchHit> _github(dynamic data, SearchProvider p, int n) {
    final root = _asMap(data);
    final items = root['items'];
    if (items is! List) {
      return _extract(data, limit: n, source: p.shortLabel);
    }
    final out = <SearchHit>[];
    for (final e in items) {
      if (e is! Map || out.length >= n) continue;
      final m = Map<String, dynamic>.from(e);
      final url = (m['html_url'] ?? m['url'] ?? '').toString();
      if (!url.startsWith('http')) continue;
      String title;
      String snippet;
      switch (p) {
        case SearchProvider.githubCode:
          final repo = m['repository'] is Map
              ? (m['repository']['full_name'] ?? '').toString()
              : '';
          final path = (m['path'] ?? '').toString();
          title = [repo, path].where((s) => s.isNotEmpty).join(' · ');
          snippet = (m['text_matches'] ?? '').toString();
          break;
        case SearchProvider.githubIssues:
          title = (m['title'] ?? '').toString();
          snippet = (m['body'] ?? '').toString();
          break;
        default:
          title = (m['full_name'] ?? m['name'] ?? '').toString();
          snippet = (m['description'] ?? '').toString();
      }
      out.add(SearchHit(
        title: title.trim().isEmpty ? _hostOf(url) : _clean(title),
        url: url,
        snippet: _clean(snippet),
        source: p.shortLabel,
      ));
    }
    return out;
  }

  static String _short(dynamic d) {
    final s = d == null ? '' : d.toString();
    final t = s.replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }

  static Map<String, dynamic> _asMap(dynamic d) {
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String) {
      try {
        final v = jsonDecode(d);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// 启发式遍历：在任意层级寻找含可识别 URL 字段的对象。
  /// 覆盖 results / items / organic / webPages.value / hits / data.web / items 等。
  static List<SearchHit> _extract(dynamic data,
      {int limit = 10, String source = ''}) {
    dynamic v = data;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return _fromText(v, limit, source);
      }
    }
    if (v == null) return const [];
    final out = <SearchHit>[];
    final seen = <String>{};

    void add(dynamic node) {
      if (out.length >= limit || node is! Map) return;
      final h = _hitFrom(node, source);
      if (h != null && seen.add(h.url)) out.add(h);
    }

    void walk(dynamic node, int depth) {
      if (depth > 9 || out.length >= limit) return;
      if (node is List) {
        for (final e in node) {
          add(e);
          walk(e, depth + 1);
          if (out.length >= limit) return;
        }
      } else if (node is Map) {
        for (final e in node.values) {
          walk(e, depth + 1);
          if (out.length >= limit) return;
        }
      }
    }

    add(v);
    walk(v, 0);
    return out;
  }

  static SearchHit? _hitFrom(Map m, String source) {
    final url = _pick(m, const [
      'url',
      'link',
      'href',
      'html_url',
      'FirstURL',
      'firstURL',
      'AbstractURL',
      'source_url',
      'sourceUrl',
      'permalink',
      'webUrl',
      'uri',
    ]);
    if (!url.startsWith('http')) return null;
    final title = _pick(m, const [
      'title',
      'name',
      'full_name',
      'Heading',
      'headline',
      'page_title',
      'result_title',
      'path',
    ]);
    final snippet = _pick(m, const [
      'snippet',
      'content',
      'description',
      'desc',
      'text',
      'Text',
      'abstract',
      'AbstractText',
      'summary',
      'body',
      'snippets',
      'highlight',
      'RawContent',
    ]);
    if (title.isEmpty && snippet.isEmpty) return null;
    return SearchHit(
      title: title.isEmpty ? _hostOf(url) : _clean(title),
      url: url,
      snippet: _clean(snippet),
      source: source,
    );
  }

  static String _pick(Map m, List<String> keys) {
    for (final k in keys) {
      if (!m.containsKey(k)) continue;
      final s = _flat(m[k]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _flat(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num || v is bool) return v.toString();
    if (v is List) {
      return v.map(_flat).where((e) => e.isNotEmpty).join(' · ').trim();
    }
    if (v is Map) {
      return _pick(v, const [
        'text',
        'content',
        'value',
        'snippet',
        'description',
        'title'
      ]);
    }
    return '';
  }

  static String _clean(String s) {
    var t = s
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > 600) t = '${t.substring(0, 600)}…';
    return t;
  }

  static String _hostOf(String u) {
    final uri = Uri.tryParse(u);
    return (uri != null && uri.host.isNotEmpty) ? uri.host : u;
  }

  /// 纯文本 / Markdown 结果解析（Jina、返回非 JSON 的自定义接口）。
  static List<SearchHit> _fromText(String text, int limit, String source) {
    final out = <SearchHit>[];
    final seen = <String>{};

    void add(String title, String url) {
      if (out.length >= limit || !url.startsWith('http') || !seen.add(url)) {
        return;
      }
      out.add(SearchHit(
        title: title.isEmpty ? _hostOf(url) : _clean(title),
        url: url,
        source: source,
      ));
    }

    for (final m in RegExp(r'\[\d+\]\s*([^\n(]*?)\s*\((https?://[^\s)]+)\)')
        .allMatches(text)) {
      add((m.group(1) ?? '').trim(), (m.group(2) ?? '').trim());
    }
    for (final m in RegExp(r'\[([^\]\n]{2,120})\]\((https?://[^\s)]+)\)')
        .allMatches(text)) {
      add((m.group(1) ?? '').trim(), (m.group(2) ?? '').trim());
    }
    return out;
  }

  static List<Citation> toCitations(List<SearchHit> hits) {
    final out = <Citation>[];
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      out.add(Citation(
        index: i + 1,
        title: h.title.isEmpty ? h.url : h.title,
        url: h.url,
        snippet: h.snippet,
        source: h.source,
      ));
    }
    return out;
  }

  static String buildContext(List<SearchHit> hits) {
    if (hits.isEmpty) return '';
    final b = StringBuffer();
    b.writeln('[联网检索结果] 以下是刚刚获取的实时资料。请优先依据这些资料作答，');
    b.writeln('并在对应事实后以 [1] [2] 的形式标注来源编号。资料不足时明确说明。');
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      b.writeln(
          '[${i + 1}] ${h.title}${h.source.isEmpty ? '' : ' · 来源 ${h.source}'}');
      b.writeln('URL: ${h.url}');
      if (h.snippet.isNotEmpty) b.writeln('摘要: ${h.snippet}');
    }
    return b.toString();
  }
}
