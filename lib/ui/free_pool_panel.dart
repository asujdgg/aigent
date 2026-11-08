import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/free_pool.dart';
import '../i18n.dart';
import '../theme.dart';

/// 设置 → 免密模型。
///
/// 只做一件事：把此刻**真的能免密钥对话**的模型列出来。判定标准是
/// 真实发一次 1 token 的请求，而不是看 /models 返回了什么。
class FreePoolPanel extends StatefulWidget {
  final bool dark;
  final List<ApiProfile> profiles;
  final Future<void> Function(
    String name,
    String baseUrl,
    String key,
    String model,
  ) onAdd;

  const FreePoolPanel({
    super.key,
    required this.dark,
    required this.profiles,
    required this.onAdd,
  });

  @override
  State<FreePoolPanel> createState() => _FreePoolPanelState();
}

class _FreePoolPanelState extends State<FreePoolPanel> {
  final List<FreeEndpoint> _custom = [];
  List<FreeHit>? _hits;
  bool _scanning = false;
  double _progress = 0;
  bool _showFailed = false;

  /// 探测通过就自动接入，省得一个个点。
  bool _autoAdopt = true;
  final Set<String> _adopted = {};

  bool get dark => widget.dark;

  List<FreeEndpoint> get _all => [
        ...kFreeEndpoints,
        ...FreePool.localFromProfiles(widget.profiles),
        ..._custom,
      ];

  /// 按提供方分组，待检测列表用，避免同一家的五个模型刷屏。
  Map<String, List<FreeEndpoint>> get _byProvider {
    final m = <String, List<FreeEndpoint>>{};
    for (final e in _all) {
      m.putIfAbsent(e.providerLabel, () => <FreeEndpoint>[]).add(e);
    }
    return m;
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _progress = 0;
      _hits = null;
    });
    final hits = await FreePool.probeAll(
      endpoints: _all,
      onProgress: (v) {
        if (mounted) setState(() => _progress = v);
      },
    );
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _progress = 1;
      _hits = hits;
      _showFailed = false;
    });
    if (_autoAdopt) await _adopt(hits);
  }

  /// 把探测通过的通道直接写进配置档。
  /// 同一个「地址 + 模型」只加一次；已经是当前连接的也跳过。
  Future<void> _adopt(List<FreeHit> hits) async {
    final existing = <String>{
      for (final p in widget.profiles) '${p.baseUrl}|${p.model}',
    };
    var n = 0;
    for (final h in hits.where((h) => h.ok)) {
      final models = h.usableModels;
      if (models.isEmpty) continue;
      final model = models.first;
      final key = '${h.baseUrl}|$model';
      if (existing.contains(key) || _adopted.contains(key)) continue;
      _adopted.add(key);
      await widget.onAdd('${h.provider} · $model', h.baseUrl, '', model);
      n++;
    }
    if (n > 0 && mounted) _snack('已自动接入 $n 个可用通道');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(),
        const SizedBox(height: 12),
        _body(),
        const SizedBox(height: 12),
        Text(t('公开实例由第三方维护，随时可能限流、改协议或下线，所以每次都要重新检测。不要在这些通道里传隐私、账号和公司资料。'),
          style: meta(dark,
              size: 11.5, height: 1.7, color: dark ? C.dInk2 : C.ink2),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 顶部

  Widget _headerCard() {
    final hits = _hits;
    final okCount = hits?.where((h) => h.ok).length ?? 0;
    final modelCount = hits == null
        ? 0
        : hits
            .where((h) => h.ok)
            .fold<int>(0, (n, h) => n + h.usableModels.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 17),
      decoration: surfaceBox(dark, shadowScale: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('四家匿名通道、十来个模型，点一次全部测完。只看模型列表会被骗：不少网关列得很全，真调用时回 402 或 429。'),
            style: meta(dark,
                size: 12, height: 1.7, color: dark ? C.dInk2 : C.ink2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _primary(_scanning ? '测试中' : (hits == null ? '一键测试' : '重新测试'),
                  busy: _scanning, onTap: _scan),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _scanning ? null : _addCustom,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.r),
                    border: Border.all(color: borderStrongOf(dark)),
                  ),
                  child: Text(t('添加地址'),
                      style: ts(dark,
                          size: 13,
                          weight: FontWeight.w500,
                          color: dark ? C.dInk : C.ink)),
                ),
              ),
              const Spacer(),
              Text(
                  hits == null
                      ? '${_all.length} 个源'
                      : '$okCount 可用 · $modelCount 模型',
                  style: meta(dark,
                      size: 11.5, color: dark ? C.dInk2 : C.ink2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('自动接入可用项'),
                        style: ts(dark,
                            size: 13, weight: FontWeight.w500, height: 1.3)),
                    const SizedBox(height: 3),
                    Text(
                      _autoAdopt
                          ? '测试通过的直接写进配置档，不用一个个点'
                          : '只显示结果，由你手动挑',
                      style: meta(dark,
                          size: 11.5,
                          height: 1.5,
                          color: dark ? C.dInk2 : C.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch.adaptive(
                value: _autoAdopt,
                activeColor: accentOf(dark),
                onChanged: (v) => setState(() => _autoAdopt = v),
              ),
            ],
          ),
          if (_scanning) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 3,
                backgroundColor: fieldOf(dark),
                valueColor: AlwaysStoppedAnimation(accentOf(dark)),
              ),
            ),
            const SizedBox(height: 8),
            Text(t('分两批并发，单个超时 25 秒；有本机服务时会更快'),
                style: meta(dark,
                    size: 11.5, color: dark ? C.dInk2 : C.ink2)),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 结果

  Widget _body() {
    final hits = _hits;
    if (hits == null) return _pendingCard();
    if (hits.isEmpty) return _emptyCard('没有可检测的来源');
    final ok = hits.where((h) => h.ok).toList();
    final bad = hits.where((h) => !h.ok).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ok.isEmpty)
          _emptyCard('这次没有来源通过。公开实例的额度通常按 IP 计，过几分钟再试，'
              '或换成自己部署的免密服务。')
        else ...[
          _bestCard(ok),
          const SizedBox(height: 10),
          for (final h in ok) ...[
            _hitCard(h),
            const SizedBox(height: 10),
          ],
        ],
        if (bad.isNotEmpty) _failedCard(bad),
      ],
    );
  }

  /// 可用时的第一张卡：一句话结论 + 一键接入最快的那个。
  Widget _bestCard(List<FreeHit> ok) {
    final best = FreePool.fastest(ok);
    if (best == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(D.cardR),
        color: accentOf(dark).withOpacity(dark ? 0.10 : 0.06),
        border: Border.all(color: accentOf(dark).withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${ok.length} 个源可用',
                    style: ts(dark,
                        size: 13.5, weight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 4),
                Text(
                    '最快 ${best.provider} · ${best.latencyMs}ms · ${best.endpoint.model}',
                    style: meta(dark,
                        size: 11.5,
                        height: 1.5,
                        color: dark ? C.dInk2 : C.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _use(best, best.usableModels.first),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentOf(dark),
                borderRadius: BorderRadius.circular(D.r),
              ),
              child: Text(t('接入最快'),
                  style: ts(dark,
                      size: 13,
                      weight: FontWeight.w600,
                      color: dark ? C.dPaper : Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    final groups = _byProvider;
    final muted = dark ? C.dInk2 : C.ink2;
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 4),
      decoration: surfaceBox(dark, shadowScale: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(t('待检测'),
                  style: ts(dark,
                      size: 13.5, weight: FontWeight.w600, height: 1.3)),
              const SizedBox(width: 8),
              Text('${_all.length} 个模型 · ${groups.length} 家',
                  style: meta(dark, size: 11.5, color: muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(t('点「一键测试」会对每家真实发一次请求，通过才列进可用。'),
              style: meta(dark, size: 11.5, height: 1.6, color: muted)),
          const SizedBox(height: 6),
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) Divider(height: 1, color: hairOf(dark)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(groups.keys.elementAt(i),
                            style: ts(dark,
                                size: 13.5,
                                weight: FontWeight.w500,
                                height: 1.3)),
                        const SizedBox(height: 3),
                        Text(
                          groups.values
                              .elementAt(i)
                              .map((e) => e.model)
                              .join(' · '),
                          style: meta(dark, size: 11.5, height: 1.45, color: muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: fieldOf(dark),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: borderStrongOf(dark)),
                    ),
                    child: Text(
                      '${groups.values.elementAt(i).length} 个模型',
                      style: meta(dark, size: 11.5, color: muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: insetBox(dark),
      child: Text(text,
          style: meta(dark,
              size: 12,
              height: 1.7,
              color: dark ? C.dInk2 : C.ink2)),
    );
  }

  Widget _hitCard(FreeHit h) {
    final models = h.usableModels;
    final shown = models.take(6).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: surfaceBox(dark, shadowScale: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: C.ok, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(h.name,
                    style: ts(dark,
                        size: 13.5, weight: FontWeight.w500, height: 1.3)),
              ),
              if (h.vision) ...[
                Text(t('视觉'),
                    style: meta(dark, size: 11.5, color: accentOf(dark))),
                const SizedBox(width: 9),
              ],
              Text('${h.latencyMs}ms',
                  style: meta(dark, size: 11.5, color: accentOf(dark))),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            h.endpoint.note.isEmpty
                ? '${h.provider} · ${models.length} 个模型'
                : '${h.endpoint.note} · ${models.length} 个模型',
            style: meta(dark,
                size: 11.5, height: 1.5, color: dark ? C.dInk2 : C.ink2),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final m in shown)
                GestureDetector(
                  onTap: () => _use(h, m),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: borderOf(dark)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m,
                            style: ts(dark, size: 13, height: 1.3)),
                        const SizedBox(width: 5),
                        Icon(Icons.add_rounded,
                            size: 12, color: accentOf(dark)),
                      ],
                    ),
                  ),
                ),
              if (models.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('+${models.length - shown.length}',
                      style: meta(dark,
                          size: 11.5, color: dark ? C.dInk2 : C.ink2)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _failedCard(List<FreeHit> bad) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(D.cardR),
        border: Border.all(color: borderOf(dark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showFailed = !_showFailed),
            child: Row(
              children: [
                Text('${bad.length} 个未通过',
                    style: meta(dark,
                        size: 12, color: dark ? C.dInk2 : C.ink2)),
                const Spacer(),
                Icon(
                  _showFailed
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: dark ? C.dInk3 : C.ink3,
                ),
              ],
            ),
          ),
          if (_showFailed) ...[
            const SizedBox(height: 6),
            for (var i = 0; i < bad.length; i++) ...[
              if (i > 0) Divider(height: 1, color: hairOf(dark)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bad[i].name, style: ts(dark, size: 13)),
                          const SizedBox(height: 3),
                          Text(bad[i].baseUrl,
                              style: meta(dark,
                                  size: 11.5,
                                  color: dark ? C.dInk2 : C.ink2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(bad[i].error,
                        style: meta(dark, size: 11.5, color: C.warn)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 动作

  Future<void> _use(FreeHit h, String model) async {
    final name =
        h.endpoint.kind == FreeKind.local ? h.name : '${h.provider} · $model';
    await widget.onAdd(name, h.baseUrl, '', model);
    _snack('已接入 $name');
  }

  Future<void> _addCustom() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('添加免密地址')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 4,
              autofocus: true,
              style: ts(dark, size: 13),
              decoration: fieldDecoration(dark,
                  hint: t('https://example.com/v1 gpt-4o-mini\n每行一个，模型名可省略')),
            ),
            const SizedBox(height: 10),
            Text(t('必须是不需要 Key 的 OpenAI 兼容地址，添加后会立刻检测一次。'),
                style: meta(dark,
                    size: 11.5, height: 1.6, color: dark ? C.dInk2 : C.ink2)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(t('添加'))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;

    final added = <FreeEndpoint>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final parts = t.split(RegExp(r'\s+'));
      final url = parts.first;
      if (!url.startsWith('http')) continue;
      final model = parts.length > 1 ? parts[1] : '';
      final host = Uri.tryParse(url)?.host ?? url;
      added.add(FreeEndpoint(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}_${added.length}',
        name: host,
        provider: host,
        baseUrl: url,
        model: model.isEmpty ? 'gpt-3.5-turbo' : model,
        note: '自定义地址',
      ));
    }
    if (added.isEmpty) {
      _snack(t('没识别到有效地址，需要以 http 开头'));
      return;
    }
    setState(() => _custom.addAll(added));

    // 只探测新加的，结果并进现有列表。
    final fresh = await FreePool.probeAll(endpoints: added);
    if (!mounted) return;
    setState(() {
      final cur = _hits ?? <FreeHit>[];
      _hits = [...fresh, ...cur];
    });
    _snack('已添加 ${added.length} 个地址');
  }

  Widget _primary(String text,
      {bool busy = false, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: busy ? accentOf(dark).withOpacity(0.5) : accentOf(dark),
          borderRadius: BorderRadius.circular(D.r),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor:
                      AlwaysStoppedAnimation(dark ? C.dPaper : Colors.white),
                ),
              )
            : Text(text,
                style: ts(dark,
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: dark ? C.dPaper : Colors.white)),
      ),
    );
  }
}
