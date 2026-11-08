import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/project_search.dart';
import '../services/relay_catalog.dart';
import '../i18n.dart';
import '../theme.dart';

/// 设置 → 网页版反代。
///
/// 四件事：扫一台主机上正在跑的兼容服务；从内置项目里挑一个接入；
/// 一键测公共实例；用 GitHub 搜目录里没有的项目。
class RelayPanel extends StatefulWidget {
  final bool dark;
  final String currentBaseUrl;
  final Future<void> Function(
    RelayPreset preset,
    String baseUrl,
    String key,
    String model,
  ) onAdd;

  const RelayPanel({
    super.key,
    required this.dark,
    required this.currentBaseUrl,
    required this.onAdd,
  });

  @override
  State<RelayPanel> createState() => _RelayPanelState();
}

class _RelayPanelState extends State<RelayPanel> {
  late final TextEditingController _host;
  late final TextEditingController _query;
  bool _scanning = false;
  double _progress = 0;
  List<RelayHit>? _hits;
  String _filter = '全部';

  // 公共实例的一键测试结果，key 是 preset.id。
  Map<String, RelayHit?> _pubHits = {};
  bool _pubTesting = false;

  // 全网搜索。
  bool _searching = false;
  List<RepoResult>? _repos;
  String _repoQuery = '';
  String _repoError = '';

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(
        text: RelayProbe.guessHost(widget.currentBaseUrl));
    _query = TextEditingController();
  }

  @override
  void dispose() {
    _host.dispose();
    _query.dispose();
    super.dispose();
  }

  bool get _dark => widget.dark;

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final raw = _host.text.trim();
    if (raw.isEmpty) {
      _snack(t('先填主机地址'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _progress = 0;
      _hits = null;
    });
    final hits = await RelayProbe.scan(
      host: raw,
      onProgress: (v) {
        if (mounted) setState(() => _progress = v);
      },
    );
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _progress = 1;
      _hits = hits;
    });
    if (hits.isEmpty) _snack(t('没有发现服务，检查反代是否已启动'));
  }

  /// 一键测试所有公共实例：只测写死的地址，不扫端口。
  Future<void> _testPublic() async {
    if (_pubTesting) return;
    final list = kRelayPresets.where((p) => p.isPublicInstance).toList();
    setState(() {
      _pubTesting = true;
      _pubHits = {};
    });
    final hits = await RelayProbe.probeAll(list);
    if (!mounted) return;
    setState(() {
      _pubTesting = false;
      _pubHits = hits;
    });
    final alive = hits.values.where((h) => h != null).length;
    _snack(alive == 0 ? '没有一个连得上，公共站换域名很常见' : '$alive / ${list.length} 个在线');
  }

  /// 全网搜索：直接查 GitHub，不限内置目录。
  Future<void> _searchWeb(String query) async {
    final q = query.trim();
    if (q.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _repoError = '';
      _repoQuery = q;
      _repos = null;
    });
    try {
      final list = await ProjectSearch.search(q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _repos = list;
        if (list.isEmpty) _repoError = '没搜到，换个词试试';
      });
    } on ProjectSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _repoError = e.message;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) {
      Clipboard.setData(ClipboardData(text: url));
      _snack(t('打不开浏览器，链接已复制'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scanCard(),
        const SizedBox(height: 18),
        _presetCard(),
      ],
    );
  }

  // ------------------------------------------------------------ 扫描

  Widget _scanCard() {
    final dark = _dark;
    final hits = _hits;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
      decoration: surfaceBox(dark, shadowScale: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 11,
                decoration: BoxDecoration(
                  color: accentOf(dark),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(t('扫描已运行的服务'), style: sectionTitle(dark)),
              const Spacer(),
              if (hits != null)
                Text('${hits.length} 个', style: meta(dark, size: 11.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(t('反代一般跑在电脑或路由器上。手机和它连同一个 Wi-Fi，填电脑的内网 IP（如 192.168.1.5），点扫描会自动试常见端口。'),
            style: meta(dark, size: 11.5, color: dark ? C.dInk2 : C.ink2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _host,
                  maxLines: 1,
                  style: ts(dark, size: 13.5),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _scan(),
                  decoration:
                      fieldDecoration(dark, hint: t('127.0.0.1 或 192.168.1.5')),
                ),
              ),
              const SizedBox(width: 10),
              _primary('扫描', busy: _scanning, onTap: _scan),
            ],
          ),
          if (_scanning) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2.5,
                backgroundColor: fieldOf(dark),
                valueColor: AlwaysStoppedAnimation(accentOf(dark)),
              ),
            ),
            const SizedBox(height: 8),
            Text('已试 ${(_progress * 100).round()}% · 端口多的机器要几秒',
                style: meta(dark, size: 11.5)),
          ],
          if (hits != null) ...[
            const SizedBox(height: 14),
            if (hits.isEmpty)
              _emptyScan()
            else
              for (var i = 0; i < hits.length; i++) ...[
                if (i > 0) Divider(height: 1, color: hairOf(dark)),
                _hitRow(hits[i]),
              ],
          ],
        ],
      ),
    );
  }

  Widget _emptyScan() {
    final dark = _dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: insetBox(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('这台主机上没有发现兼容端点。'), style: ts(dark, size: 13)),
          const SizedBox(height: 5),
          Text(t('依次确认：服务已启动、端口对得上、防火墙放行该端口、手机没有连到访客网络。'),
            style: meta(dark, size: 11.5, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _hitRow(RelayHit h) {
    final dark = _dark;
    final tint = h.ok ? C.ok : C.warn;
    return InkWell(
      onTap: () => _useHit(h),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.title, style: ts(dark, size: 13)),
                  const SizedBox(height: 3),
                  Text(
                    '${h.host}:${h.port} · ${h.latencyMs}ms'
                    '${h.models.isEmpty ? '' : ' · ${h.models.length} 个模型'}'
                    '${h.needsKey ? ' · 需要密钥' : ''}',
                    style: meta(dark, size: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(t('接入'),
                style: ts(dark,
                    size: 13,
                    weight: FontWeight.w600,
                    color: accentOf(dark))),
          ],
        ),
      ),
    );
  }

  Future<void> _useHit(RelayHit h) async {
    final preset = h.preset ??
        RelayPreset(
          id: 'scan_${h.port}',
          name: h.models.isNotEmpty ? h.models.first : '本机服务',
          owner: '${h.host}:${h.port}',
          summary: '扫描发现的服务',
          deploy: '',
          port: h.port,
          path: '/v1',
          auth: RelayAuth.optional,
          models: h.models.take(6).toList(),
        );
    await _openSheet(preset, presetBase: h.baseUrl, presetModels: h.models);
  }

  // ------------------------------------------------------------ 预设列表

  Widget _presetCard() {
    final dark = _dark;
    final list = kRelayPresets.where(_matches).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 14),
      decoration: surfaceBox(dark, shadowScale: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 11,
                decoration: BoxDecoration(
                  color: accentOf(dark),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(t('反代与网关'), style: sectionTitle(dark)),
              const Spacer(),
              Text('${list.length} / ${kRelayPresets.length}',
                  style: meta(dark, size: 11.5)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            maxLines: 1,
            style: ts(dark, size: 13),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) => _searchWeb(v),
            decoration:
                fieldDecoration(dark, hint: t('搜项目、平台或模型，如 deepseek / kimi / 网关')),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text('内置 ${kRelayPresets.length} 个', style: meta(dark, size: 11.5)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _searching ? null : () => _searchWeb(_query.text),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_rounded,
                        size: 13, color: accentOf(dark)),
                    const SizedBox(width: 5),
                    Text(_searching ? '搜索中…' : '全网搜索',
                        style: ts(dark,
                            size: 13,
                            color: accentOf(dark),
                            weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (!_searching && _repos == null && _repoError.isEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in ProjectSearch.quickQueries)
                  GestureDetector(
                    onTap: () {
                      _query.text = q;
                      setState(() {});
                      _searchWeb(q);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderOf(dark)),
                      ),
                      child: Text(q, style: meta(dark, size: 11.5)),
                    ),
                  ),
              ],
            ),
          ],
          if (_repos != null || _repoError.isNotEmpty) ...[
            const SizedBox(height: 10),
            _webResults(),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final t in kRelayTags)
                _tag(t, active: _filter == t, onTap: () {
                  setState(() => _filter = t);
                }),
            ],
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child:
                  Text(t('没有匹配的项目，换个关键词或点「全部」。'), style: meta(dark, size: 11.5)),
            )
          else
            for (final g in _groupOrder) ..._groupSection(g, list),
          const SizedBox(height: 10),
          Text(t('8000 和 3000 被多个项目共用，同一台机器只能起一个；要同时用就改端口或分开部署。官方那组要 Key，只是有免费额度；公益实例是别人的服务，随时可能下线，别放隐私内容。'),
            style: meta(dark, size: 11.5, height: 1.6),
          ),
          const SizedBox(height: 9),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openUrl(kWelfareIndexUrl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_rounded, size: 12, color: accentOf(dark)),
                const SizedBox(width: 5),
                // 大字号 / 窄屏下这行会顶出卡片，允许折行。
                Flexible(
                  child: Text(t('公益站额度导航 · 社区持续更新'),
                      style: ts(dark, size: 13, color: accentOf(dark))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 全网搜索结果。点一条直接用浏览器打开仓库。
  Widget _webResults() {
    final dark = _dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: insetBox(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('GitHub · $_repoQuery',
                    style: meta(dark, size: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _repos = null;
                  _repoError = '';
                }),
                child: Icon(Icons.close_rounded,
                    size: 14, color: dark ? C.dInk3 : C.ink3),
              ),
            ],
          ),
          if (_repoError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_repoError,
                  style: meta(dark, size: 11.5, height: 1.5, color: C.warn)),
            )
          else
            for (var i = 0; i < _repos!.length; i++) ...[
              if (i > 0) Divider(height: 1, color: hairOf(dark)),
              InkWell(
                onTap: () => _openUrl(_repos![i].url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(_repos![i].fullName,
                                style: ts(dark, size: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.open_in_new_rounded,
                              size: 12, color: accentOf(dark)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(_repos![i].description,
                          style: meta(dark, size: 11.5, height: 1.45),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(_repos![i].metaLine,
                          style: meta(dark, size: 11.5, color: accentOf(dark))),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  static const List<RelayGroup> _groupOrder = [
    RelayGroup.web,
    RelayGroup.gateway,
    RelayGroup.welfare,
    RelayGroup.official,
    RelayGroup.local,
  ];

  String _groupLabel(RelayGroup g) => switch (g) {
        RelayGroup.web => '网页版反代 · 自己部署',
        RelayGroup.gateway => '自建网关',
        RelayGroup.welfare => '公益与公共实例 · 用对方发的 Key',
        RelayGroup.official => '官方接口 · 需 Key，有免费额度',
        RelayGroup.local => '本机推理',
      };

  List<Widget> _groupSection(RelayGroup g, List<RelayPreset> all) {
    final items = all.where((p) => p.group == g).toList();
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(_groupLabel(g), style: meta(_dark, size: 11.5)),
            ),
            if (g == RelayGroup.welfare)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pubTesting ? null : _testPublic,
                child: Text(_pubTesting ? '测试中…' : '一键测试',
                    style: ts(_dark,
                        size: 13,
                        color: accentOf(_dark),
                        weight: FontWeight.w600)),
              ),
          ],
        ),
      ),
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Divider(height: 1, color: hairOf(_dark)),
        _presetRow(items[i]),
      ],
    ];
  }

  bool _matches(RelayPreset p) {
    if (_filter != '全部' && !p.tags.contains(_filter)) return false;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) ||
        p.owner.toLowerCase().contains(q) ||
        p.summary.toLowerCase().contains(q) ||
        p.id.toLowerCase().contains(q) ||
        p.tags.any((t) => t.toLowerCase().contains(q)) ||
        p.models.any((m) => m.toLowerCase().contains(q));
  }

  Widget _tag(String text,
      {required bool active, required VoidCallback onTap}) {
    final dark = _dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: D.animFast,
        curve: D.curve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? accentOf(dark) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? accentOf(dark) : borderOf(dark),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: meta(dark,
              size: 11.5,
              color: active
                  ? (dark ? C.dPaper : Colors.white)
                  : (dark ? C.dInk2 : C.ink2)),
        ),
      ),
    );
  }

  /// 公共实例右侧的状态：未测 / 离线 / 在线（需 Key）。
  Widget _pubStatus(RelayPreset p) {
    final dark = _dark;
    final known = _pubHits.containsKey(p.id);
    if (!known) {
      return Text(t('未测'), style: meta(dark, size: 11.5));
    }
    final hit = _pubHits[p.id];
    if (hit == null) {
      return Text(t('离线'), style: meta(dark, size: 11.5, color: C.warn));
    }
    if (hit.needsKey) {
      return Text(t('在线 · 需 Key'),
          style: meta(dark, size: 11.5, color: accentOf(dark)));
    }
    return Text('在线 ${hit.latencyMs}ms',
        style: meta(dark, size: 11.5, color: C.ok));
  }

  Widget _presetRow(RelayPreset p) {
    final dark = _dark;
    return InkWell(
      onTap: () => _openSheet(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.name,
                            style: ts(dark, size: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (p.abilities.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Text(p.abilities.join(' / '),
                            style:
                                meta(dark, size: 11.5, color: accentOf(dark))),
                      ],
                      if (p.archived) ...[
                        const SizedBox(width: 7),
                        Text(t('已停更'), style: meta(dark, size: 11.5, color: C.warn)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(p.summary,
                      style: meta(dark, size: 11.5, height: 1.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (p.isPublicInstance)
                  _pubStatus(p)
                else
                  Text(p.isOfficial ? '官方' : ':${p.port}',
                      style: meta(dark, size: 11.5, color: accentOf(dark))),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 15, color: dark ? C.dInk3 : C.ink3),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 接入面板

  Future<void> _openSheet(
    RelayPreset p, {
    String? presetBase,
    List<String>? presetModels,
  }) async {
    final hostRaw = _host.text.trim();
    final target = RelayProbe.parseTarget(hostRaw);
    // 预设一律按项目默认端口填；用户改过端口就在地址框里直接改。
    final base = presetBase ?? p.urlFor(target.host, scheme: target.scheme);
    final models = presetModels != null && presetModels.isNotEmpty
        ? presetModels
        : p.models;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RelaySheet(
        dark: _dark,
        preset: p,
        initialBase: base,
        initialModels: models,
        loopback: RelayProbe.isLoopback(target.host),
        onAdd: widget.onAdd,
        onDone: (msg) {
          Navigator.pop(ctx);
          _snack(msg);
        },
      ),
    );
  }

  Widget _primary(String text,
      {bool busy = false, required VoidCallback onTap}) {
    final dark = _dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: D.animFast,
        curve: D.curve,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 18),
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
                    size: 13,
                    weight: FontWeight.w600,
                    color: dark ? C.dPaper : Colors.white)),
      ),
    );
  }
}

/// 单个预设的接入面板：部署命令、地址、密钥、模型、测试、接入。
class _RelaySheet extends StatefulWidget {
  final bool dark;
  final RelayPreset preset;
  final String initialBase;
  final List<String> initialModels;
  final bool loopback;
  final Future<void> Function(
    RelayPreset preset,
    String baseUrl,
    String key,
    String model,
  ) onAdd;
  final void Function(String msg) onDone;

  const _RelaySheet({
    required this.dark,
    required this.preset,
    required this.initialBase,
    required this.initialModels,
    required this.loopback,
    required this.onAdd,
    required this.onDone,
  });

  @override
  State<_RelaySheet> createState() => _RelaySheetState();
}

class _RelaySheetState extends State<_RelaySheet> {
  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _testing = false;
  String _testMsg = '';
  bool _testOk = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _base = TextEditingController(text: widget.initialBase);
    _key = TextEditingController();
    _model = TextEditingController(
        text: widget.initialModels.isEmpty ? '' : widget.initialModels.first);
  }

  @override
  void dispose() {
    _base.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  bool get dark => widget.dark;

  Future<void> _test() async {
    if (_testing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _testMsg = '';
      _testOk = false;
    });
    final hit = await RelayProbe.probeUrl(
      _base.text,
      key: _key.text,
      preset: widget.preset,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (hit == null) {
        _testOk = false;
        _testMsg = '连不上。确认服务已启动、地址和端口对得上、手机能访问这台机器。';
      } else if (hit.needsKey) {
        _testOk = false;
        _testMsg = '服务在跑，但拒绝了请求（401）：密钥没填或已过期。';
      } else {
        _testOk = true;
        _testMsg = hit.models.isEmpty
            ? '连通正常（${hit.latencyMs}ms），模型列表为空，可手动填模型名。'
            : '连通正常（${hit.latencyMs}ms），可用 ${hit.models.length} 个模型。';
        if (widget.initialModels.isEmpty && hit.models.isNotEmpty) {
          _model.text = hit.models.first;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_adding) return;
    final base = _base.text.trim();
    if (base.isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = '地址不能为空';
      });
      return;
    }
    final model = _model.text.trim();
    if (model.isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = '填一个模型名，或点「测试」让它自动取第一个。';
      });
      return;
    }
    setState(() => _adding = true);
    await widget.onAdd(widget.preset, base, _key.text.trim(), model);
    if (!mounted) return;
    widget.onDone('已接入「${widget.preset.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom;
    // 键盘弹出时先扣掉键盘高度再算上限，否则弹层会被顶出屏幕。
    final maxH = (mq.size.height - bottom) * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: surfaceOf(dark),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(D.floatR)),
          border: Border.all(color: borderOf(dark)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 3.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: borderOf(dark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: ts(dark, size: 17, weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                            p.isPublicInstance
                                ? '${p.owner} · 公共地址'
                                : p.isOfficial
                                    ? '${p.owner} · 官方地址'
                                    : '${p.owner} · 默认 ${p.port} 端口',
                            style: meta(dark, size: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: dark ? C.dInk3 : C.ink3),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(p.summary,
                  style: ts(dark,
                      size: 13,
                      color: dark ? C.dInk2 : C.ink2,
                      height: 1.65)),
              if (p.abilities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(p.abilities.join(' · '),
                    style: meta(dark, size: 11.5, color: accentOf(dark))),
              ],
              if (p.repoUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await launchUrl(Uri.parse(p.repoUrl),
                        mode: LaunchMode.externalApplication);
                    if (!ok) {
                      Clipboard.setData(ClipboardData(text: p.repoUrl));
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text(t('链接已复制')),
                            duration: const Duration(seconds: 1)),
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 12, color: accentOf(dark)),
                      const SizedBox(width: 5),
                      Text(p.isPublicInstance ? '打开站点 / 领 Key' : '打开仓库',
                          style: meta(dark, size: 11.5, color: accentOf(dark))),
                    ],
                  ),
                ),
              ],
              if (p.deploy.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(t('部署'), style: sectionTitle(dark)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: p.deploy));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(t('命令已复制')),
                              duration: const Duration(seconds: 1)),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_all_outlined,
                              size: 12, color: accentOf(dark)),
                          const SizedBox(width: 4),
                          Text(t('复制'),
                              style:
                                  meta(dark, size: 11.5, color: accentOf(dark))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: insetBox(dark),
                  child: Text(
                    p.deploy,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.65,
                      color: dark ? C.dInk : C.ink,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(t('接口地址'), style: sectionTitle(dark)),
              const SizedBox(height: 7),
              TextField(
                controller: _base,
                maxLines: 1,
                style: ts(dark, size: 13),
                decoration: fieldDecoration(dark,
                    hint: p.urlFor('192.168.1.5', scheme: 'http')),
              ),
              if (widget.loopback && !p.isOfficial && !p.isPublicInstance) ...[
                const SizedBox(height: 7),
                Text(t('127.0.0.1 在手机上指向手机自己。反代如果不在这台手机上，把它换成运行反代之电脑的内网 IP。'),
                  style: meta(dark, size: 11.5, height: 1.55, color: C.warn),
                ),
              ],
              if (p.auth != RelayAuth.none) ...[
                const SizedBox(height: 16),
                Text(t('密钥'), style: sectionTitle(dark)),
                const SizedBox(height: 7),
                TextField(
                  controller: _key,
                  maxLines: 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: ts(dark, size: 13),
                  decoration: fieldDecoration(dark,
                      hint: p.keyHint.isEmpty ? '填入该项目的令牌' : p.keyHint),
                ),
                if (p.auth == RelayAuth.optional) ...[
                  const SizedBox(height: 6),
                  Text(t('可留空，留空时请求不带 Authorization。'),
                      style: meta(dark, size: 11.5)),
                ],
              ],
              const SizedBox(height: 16),
              Text(t('模型'), style: sectionTitle(dark)),
              const SizedBox(height: 7),
              TextField(
                controller: _model,
                maxLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                style: ts(dark, size: 13),
                decoration: fieldDecoration(dark, hint: t('如 ${p.sampleModel}')),
              ),
              if (widget.initialModels.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final m in widget.initialModels.take(6))
                      GestureDetector(
                        onTap: () => setState(() => _model.text = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: _model.text == m
                                ? accentOf(dark).withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: _model.text == m
                                  ? accentOf(dark).withOpacity(0.5)
                                  : borderOf(dark),
                            ),
                          ),
                          child: Text(m,
                              style: meta(dark,
                                  size: 11.5,
                                  color: _model.text == m
                                      ? accentOf(dark)
                                      : (dark ? C.dInk2 : C.ink2))),
                        ),
                      ),
                  ],
                ),
              ],
              if (_testMsg.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _testOk ? C.ok : C.warn,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_testMsg,
                          style: meta(dark, size: 11.5, height: 1.6)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _testing ? null : _test,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(D.r),
                          border: Border.all(color: borderOf(dark)),
                        ),
                        child: _testing
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  valueColor:
                                      AlwaysStoppedAnimation(accentOf(dark)),
                                ),
                              )
                            : Text(t('测试连通'),
                                style: ts(dark,
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: dark ? C.dInk2 : C.ink2)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _adding ? null : _submit,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _adding
                              ? accentOf(dark).withOpacity(0.5)
                              : accentOf(dark),
                          borderRadius: BorderRadius.circular(D.r),
                        ),
                        child: _adding
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  valueColor: AlwaysStoppedAnimation(
                                      dark ? C.dPaper : Colors.white),
                                ),
                              )
                            : Text(t('接入'),
                                style: ts(dark,
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: dark ? C.dPaper : Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                p.isPublicInstance
                    ? '这是第三方公共服务，不是你自己部署的：地址随时会变，'
                        '额度按对方规则给，别把账号、隐私或公司资料发过去。'
                    : '这些项目由第三方维护，接口随对方网页改版可能失效。'
                        '只接入你自己部署的实例，不要填来路不明的公共地址。',
                style: meta(dark, size: 11.5, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
