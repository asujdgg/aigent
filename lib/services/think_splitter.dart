/// 把流式正文里的「思考段」拆出来。
///
/// 很多 OpenAI 兼容网关（DeepSeek-R1、QwQ、各类中转）并不返回
/// `reasoning_content` 字段，而是把思考直接写进 content：
///
/// ```
/// <thinking>用户问的是……先看前提……</thinking>
/// 结论是……
/// ```
///
/// 如果不拆，用户会看到一大段自我对话混在答案正文里；而如果整段丢掉，
/// 又会出现「深度思考看不到在思考什么」。这里做增量拆分：思考进思考区，
/// 正文只留答案。
///
/// 流式下标签会被切成两半（`<thi` + `nking>`），所以未闭合的尾巴要留下来
/// 等下一个 chunk，不能提前吐出去。
class ThinkSplitter {
  bool _inside = false;

  /// 可能是半个标签的尾巴，等下一块拼上再判断。
  String _tail = '';

  static const List<String> _openTags = [
    '<thinking>',
    '<think>',
    '<reasoning>',
    '<thought>',
    '<思考>',
  ];

  static const List<String> _closeTags = [
    '</thinking>',
    '</think>',
    '</reasoning>',
    '</thought>',
    '</思考>',
  ];

  bool get inside => _inside;

  /// 输入一块增量，返回拆分后的正文与思考。
  ThinkPiece add(String chunk) {
    if (chunk.isEmpty) return const ThinkPiece();
    final text = _tail + chunk;
    _tail = '';
    return _scan(text);
  }

  /// 流结束时调用，吐出残留的尾巴。
  ThinkPiece flush() {
    if (_tail.isEmpty) return const ThinkPiece();
    final rest = _tail;
    _tail = '';
    return _inside ? ThinkPiece(thinking: rest) : ThinkPiece(content: rest);
  }

  ThinkPiece _scan(String text) {
    final content = StringBuffer();
    final thinking = StringBuffer();
    var i = 0;
    while (i < text.length) {
      if (!_inside) {
        final hit = _next(text, i, _openTags);
        if (hit == null) {
          // 末尾可能是半个开标签，留到下一块。
          final keep = _partialTail(text, i, _openTags);
          content.write(text.substring(i, text.length - keep));
          if (keep > 0) _tail = text.substring(text.length - keep);
          break;
        }
        content.write(text.substring(i, hit.index));
        _inside = true;
        i = hit.index + hit.length;
      } else {
        final hit = _next(text, i, _closeTags);
        if (hit == null) {
          final keep = _partialTail(text, i, _closeTags);
          thinking.write(text.substring(i, text.length - keep));
          if (keep > 0) _tail = text.substring(text.length - keep);
          break;
        }
        thinking.write(text.substring(i, hit.index));
        _inside = false;
        i = hit.index + hit.length;
      }
    }
    return ThinkPiece(content: content.toString(), thinking: thinking.toString());
  }

  _Hit? _next(String s, int from, List<String> tags) {
    _Hit? best;
    for (final t in tags) {
      final idx = s.indexOf(t, from);
      if (idx < 0) continue;
      if (best == null || idx < best.index) best = _Hit(idx, t.length);
    }
    return best;
  }

  /// 末尾若正好是某个标签的前缀（如 `<thi`），返回需要保留的字符数。
  int _partialTail(String s, int from, List<String> tags) {
    final avail = s.length - from;
    final max = avail < 16 ? avail : 16;
    for (var len = max; len >= 1; len--) {
      final tail = s.substring(s.length - len);
      for (final t in tags) {
        if (t.length > len && t.startsWith(tail)) return len;
      }
    }
    return 0;
  }
}

class _Hit {
  final int index;
  final int length;
  const _Hit(this.index, this.length);
}

class ThinkPiece {
  final String content;
  final String thinking;
  const ThinkPiece({this.content = '', this.thinking = ''});
  bool get isEmpty => content.isEmpty && thinking.isEmpty;
}
