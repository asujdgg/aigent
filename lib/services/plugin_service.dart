import 'dart:convert';
import 'package:dio/dio.dart';

class ApiParam {
  final String name;
  final String location;
  final String type;
  final bool required;

  const ApiParam({
    required this.name,
    required this.location,
    this.type = 'string',
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        'type': type,
        'required': required,
      };

  factory ApiParam.fromJson(Map<dynamic, dynamic> j) => ApiParam(
        name: (j['name'] ?? '').toString(),
        location: (j['location'] ?? 'query').toString(),
        type: (j['type'] ?? 'string').toString(),
        required: j['required'] == true,
      );
}

class ApiOperation {
  final String id;
  final String method;
  final String path;
  final String summary;
  final List<ApiParam> params;
  final Map<String, dynamic> bodySchema;

  const ApiOperation({
    required this.id,
    required this.method,
    required this.path,
    required this.summary,
    required this.params,
    this.bodySchema = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'summary': summary,
        'params': params.map((e) => e.toJson()).toList(),
        'bodySchema': bodySchema,
      };

  factory ApiOperation.fromJson(Map<dynamic, dynamic> j) => ApiOperation(
        id: (j['id'] ?? '').toString(),
        method: (j['method'] ?? 'get').toString(),
        path: (j['path'] ?? '/').toString(),
        summary: (j['summary'] ?? '').toString(),
        params: ((j['params'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => ApiParam.fromJson(e))
            .toList(),
        bodySchema: j['bodySchema'] is Map
            ? Map<String, dynamic>.from(j['bodySchema'] as Map)
            : const {},
      );
}

/// 从 Swagger / OpenAPI JSON 生成工具清单，并代理模型发起真实 HTTP 请求。
class OpenApiPlugin {
  final String source;
  final String title;
  final String baseUrl;
  final List<ApiOperation> operations;
  final int loadedAt;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
  ));

  OpenApiPlugin({
    required this.source,
    required this.title,
    required this.baseUrl,
    required this.operations,
    int? loadedAt,
  }) : loadedAt = loadedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'source': source,
        'title': title,
        'baseUrl': baseUrl,
        'operations': operations.map((e) => e.toJson()).toList(),
        'loadedAt': loadedAt,
      };

  factory OpenApiPlugin.fromJson(Map<dynamic, dynamic> j) => OpenApiPlugin(
        source: (j['source'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        baseUrl: (j['baseUrl'] ?? '').toString(),
        operations: ((j['operations'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => ApiOperation.fromJson(e))
            .toList(),
        loadedAt: (j['loadedAt'] as num?)?.toInt(),
      );

  static Future<OpenApiPlugin> load(String url, {String? apiKey}) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      validateStatus: (_) => true,
    ));
    final resp = await dio.get<dynamic>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          if (apiKey != null && apiKey.isNotEmpty)
            'Authorization': 'Bearer $apiKey'
        },
      ),
    );
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw StateError('拉取 OpenAPI 文档失败：HTTP $code');
    }
    final raw = resp.data;
    Map<String, dynamic> doc;
    try {
      final v = raw is String ? jsonDecode(raw) : raw;
      if (v is! Map) throw StateError('文档根节点不是对象');
      doc = Map<String, dynamic>.from(v);
    } catch (e) {
      throw StateError('OpenAPI 文档不是合法 JSON：$e');
    }

    final src = Uri.tryParse(url);
    var base = '';
    final servers = doc['servers'];
    if (servers is List && servers.isNotEmpty && servers.first is Map) {
      base = (servers.first['url'] ?? '').toString();
    }
    if (base.isEmpty) {
      final host = (doc['host'] ?? '').toString();
      if (host.isNotEmpty) {
        final schemes = doc['schemes'];
        final scheme = (schemes is List && schemes.isNotEmpty)
            ? schemes.first.toString()
            : (src?.scheme.isNotEmpty == true ? src!.scheme : 'https');
        base = '$scheme://$host${(doc['basePath'] ?? '').toString()}';
      }
    }
    if (base.isEmpty && src != null) {
      base = '${src.scheme}://${src.host}${src.hasPort ? ':${src.port}' : ''}';
    }
    if (base.startsWith('/') && src != null) {
      base = src.resolve(base).toString();
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    final info = doc['info'];
    final title =
        info is Map ? (info['title'] ?? 'OpenAPI 插件').toString() : 'OpenAPI 插件';

    final ops = <ApiOperation>[];
    final paths = doc['paths'];
    const methods = {'get', 'post', 'put', 'patch', 'delete'};
    if (paths is Map) {
      paths.forEach((pathKey, methodsMap) {
        if (methodsMap is! Map) return;
        final common = methodsMap['parameters'];
        methodsMap.forEach((mKey, op) {
          final method = mKey.toString().toLowerCase();
          if (!methods.contains(method) || op is! Map) return;
          final operation = Map<String, dynamic>.from(op);
          final ps = <ApiParam>[];
          void collect(dynamic list) {
            if (list is! List) return;
            for (final p in list) {
              if (p is! Map) continue;
              final pm = Map<String, dynamic>.from(p);
              final loc = (pm['in'] ?? 'query').toString();
              final schema = pm['schema'];
              ps.add(ApiParam(
                name: (pm['name'] ?? '').toString(),
                location: loc,
                type: schema is Map
                    ? (schema['type'] ?? 'string').toString()
                    : 'string',
                required: pm['required'] == true,
              ));
            }
          }

          collect(common);
          collect(operation['parameters']);

          Map<String, dynamic> bodySchema = const {};
          final rb = operation['requestBody'];
          if (rb is Map) {
            final content = rb['content'];
            if (content is Map) {
              dynamic ct = content['application/json'];
              if (ct == null) {
                for (final v in content.values) {
                  ct = v;
                  break;
                }
              }
              if (ct is Map && ct['schema'] is Map) {
                bodySchema = Map<String, dynamic>.from(ct['schema'] as Map);
              }
            }
          }
          if (bodySchema['properties'] is Map) {
            (bodySchema['properties'] as Map).forEach((k, v) {
              ps.add(ApiParam(
                name: k.toString(),
                location: 'body',
                type: v is Map ? (v['type'] ?? 'string').toString() : 'string',
                required: (bodySchema['required'] is List) &&
                    (bodySchema['required'] as List).contains(k),
              ));
            });
          }

          final safe = '$method ${pathKey.toString()}'
              .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
          final id = (operation['operationId'] ?? safe).toString();
          ops.add(ApiOperation(
            id: id,
            method: method,
            path: pathKey.toString(),
            summary: (operation['summary'] ?? operation['description'] ?? '')
                .toString(),
            params: ps,
            bodySchema: bodySchema,
          ));
        });
      });
    }
    if (ops.isEmpty) throw StateError('文档中没有可调用的 paths 操作');
    return OpenApiPlugin(
        source: url, title: title, baseUrl: base, operations: ops);
  }

  String get toolPrompt {
    final b = StringBuffer();
    b.writeln('[外部工具] 你可以调用 HTTP 插件 API 来完成任务。');
    b.writeln('需要调用工具时，只输出下面这一行 JSON，不要附加解释：');
    b.writeln('{"tool":"操作ID","arguments":{"参数名":"值"}}');
    b.writeln('可用工具（来自 $title，共 ${operations.length} 个）：');
    for (final o in operations.take(50)) {
      final args = o.params.isEmpty
          ? '无参数'
          : o.params
              .map((p) => '${p.name}(${p.location}${p.required ? ',必填' : ''})')
              .join(', ');
      b.writeln(
          '- ${o.id} | ${o.method.toUpperCase()} ${o.path} | ${o.summary} | 参数: $args');
    }
    b.writeln('你会收到工具返回的结果，然后请用自然语言给出最终答案，不要再输出工具 JSON。');
    return b.toString();
  }

  /// 从模型输出中定位工具调用 JSON（支持 fenced block 与内联对象，括号平衡扫描）。
  static Map<String, dynamic>? parseToolCall(String text) {
    final fenced =
        RegExp(r'```(?:tool|json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final m in fenced.allMatches(text)) {
      final j = _try(text: m.group(1) ?? '');
      if (j != null) return j;
    }
    final whole = _try(text: text.trim());
    if (whole != null) return whole;

    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x7B) continue; // '{'
      var depth = 0;
      var inStr = false;
      var esc = false;
      for (var j = i; j < text.length; j++) {
        final c = text[j];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == r'\') {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
          continue;
        }
        if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            final r = _try(text: text.substring(i, j + 1));
            if (r != null) return r;
            break;
          }
        }
      }
    }
    return null;
  }

  static Map<String, dynamic>? _try({required String text}) {
    final t = text.trim();
    if (!t.startsWith('{')) return null;
    try {
      final v = jsonDecode(t);
      if (v is Map && v['tool'] != null) {
        final args = v['arguments'] ?? v['args'] ?? v['parameters'];
        return {
          'tool': v['tool'].toString(),
          'arguments': args is Map
              ? Map<String, dynamic>.from(args)
              : <String, dynamic>{},
        };
      }
    } catch (_) {}
    return null;
  }

  ApiOperation? find(String id) {
    for (final o in operations) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<String> call(String opId, Map<String, dynamic> args,
      {String? apiKey}) async {
    final op = find(opId);
    if (op == null) throw StateError('未知工具：$opId');

    var path = op.path;
    final query = <String, dynamic>{};
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
    };
    final body = <String, dynamic>{};

    for (final e in args.entries) {
      if (path.contains('{${e.key}}')) {
        path = path.replaceAll(
            '{${e.key}}', Uri.encodeComponent(e.value.toString()));
        continue;
      }
      ApiParam? meta;
      for (final p in op.params) {
        if (p.name == e.key) {
          meta = p;
          break;
        }
      }
      final loc = meta?.location ?? (op.method == 'get' ? 'query' : 'body');
      switch (loc) {
        case 'path':
          break;
        case 'header':
          headers[e.key] = e.value.toString();
          break;
        case 'body':
          body[e.key] = e.value;
          break;
        default:
          query[e.key] = e.value;
      }
    }

    final uri = baseUrl + (path.startsWith('/') ? path : '/$path');
    final resp = await _dio.request<dynamic>(
      uri,
      queryParameters: query.isEmpty ? null : query,
      data: body.isEmpty ? null : jsonEncode(body),
      options: Options(
        method: op.method.toUpperCase(),
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    var out = resp.data == null ? '' : resp.data.toString();
    if (out.length > 8000) out = '${out.substring(0, 8000)}\n…（结果已截断）';
    return 'HTTP ${resp.statusCode}\n$out';
  }
}
