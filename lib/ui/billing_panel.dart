import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../services/price_catalog.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 设置 → 费用与价格：接上接口后按真实 token 算钱，并支持拉取实时公开报价。
class BillingPanel extends StatefulWidget {
  const BillingPanel({super.key, required this.dark});

  final bool dark;

  @override
  State<BillingPanel> createState() => _BillingPanelState();
}

class _BillingPanelState extends State<BillingPanel> {
  bool _busy = false;
  String _msg = '';

  bool get dark => widget.dark;

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    final st = context.read<AppState>();
    String m;
    try {
      m = await st.refreshPrices();
    } catch (e) {
      m = '${t('拉取失败')}：$e';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = m;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.settings;
    final stats = st.tokenStats;
    final total = st.totalCost;
    final today = st.todayCost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sec(t('花了多少钱'), [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(total == null ? '—' : '¥ ${total.toStringAsFixed(4)}',
                  style: display(dark, size: 32)),
              const SizedBox(width: 8),
              Text(t('累计估算'), style: meta(dark, size: 11.5)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _stat(t('今日'),
                      today == null ? '—' : '¥ ${today.toStringAsFixed(4)}')),
              const SizedBox(width: 8),
              Expanded(child: _stat(t('请求次数'), '${stats.requests}')),
              const SizedBox(width: 8),
              Expanded(
                  child: _stat(t('缓存省下'),
                      st.cacheSaving > 0
                          ? '¥ ${st.cacheSaving.toStringAsFixed(3)}'
                          : '—')),
            ],
          ),
          const SizedBox(height: 10),
          Text(t('费用 = 网关返回的真实 token 数 × 单价。网关没返回 usage 时按字符估算，会略偏。这里只做本地自查，正式账单以服务商后台为准。'),
              style: meta(dark, size: 11.5, height: 1.55)),
        ]),

        _sec(t('实时价格'), [
          SwitchRow(
            title: t('自动获取实时价格'),
            subtitle: t('启动后在后台拉取公开费率表，按当前模型自动匹配单价；用量数据不会上传。'),
            value: s.priceAuto,
            icon: Icons.price_change_outlined,
            onChanged: (v) => st.patch((x) => x.priceAuto = v),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _busy ? null : _refresh,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _busy ? fieldOf(dark) : C.brand,
                borderRadius: BorderRadius.circular(D.r),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(t('刷新实时价格'),
                      style: ts(dark,
                          size: 13,
                          weight: FontWeight.w600,
                          color: Colors.white)),
            ),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_msg, style: sub(dark, size: 12)),
          ],
          const SizedBox(height: 12),
          _kv(t('价格来源'), s.priceSource.isEmpty ? t('尚未获取') : s.priceSource),
          _kv(t('匹配模型'),
              s.priceMatchedModel.isEmpty ? t('未匹配') : s.priceMatchedModel),
          _kv(t('更新时间'), s.priceUpdatedAt == 0 ? '—' : _time(s.priceUpdatedAt)),
          const SizedBox(height: 6),
          _note(t('OpenAI / Anthropic 等官方接口没有「按次返回单价」的公开端点，账单查询需要单独的 Admin Key，客户端不该持有。因此这里从 LiteLLM / OpenRouter 的公开费率表取价，再乘以本地已记录的真实 token 数。')),
        ]),

        _sec(t('单价与汇率'), [
          _row(t('输入单价'), '¥ ${s.priceInPerM.toStringAsFixed(2)} / ${t('百万')}',
              () => _edit(t('输入单价'), s.priceInPerM,
                  (v) => st.patch((x) => x.priceInPerM = v))),
          _row(t('输出单价'), '¥ ${s.priceOutPerM.toStringAsFixed(2)} / ${t('百万')}',
              () => _edit(t('输出单价'), s.priceOutPerM,
                  (v) => st.patch((x) => x.priceOutPerM = v))),
          _row(t('美元汇率'), '1 USD = ¥ ${s.usdToCny.toStringAsFixed(2)}',
              () => _edit(t('美元汇率'), s.usdToCny,
                  (v) => st.patch((x) => x.usdToCny = v.clamp(0.1, 100)))),
          const SizedBox(height: 6),
          Text(t('单价填 0 表示不计算费用；手填单价不会被实时价格覆盖，除非主动刷新。'),
              style: meta(dark, size: 11.5, height: 1.5)),
        ]),

        if (stats.byModel.isNotEmpty)
          _sec(t('按模型花费'), [
            ...stats.byModel.entries.map((e) {
              final p = st.priceFor(e.key);
              final c = PriceCatalog.costOf(
                prompt: e.value.prompt,
                completion: e.value.completion,
                inputPerM: p.input,
                outputPerM: p.output,
                cachedTokens: e.value.cached.toDouble(),
                cachedPerM: p.cached,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.key.isEmpty ? t('未指定模型') : e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(dark, size: 12.5)),
                    ),
                    const SizedBox(width: 8),
                    Text('¥ ${c.toStringAsFixed(4)}',
                        style: ts(dark, size: 12.5, weight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ]),

        if (stats.days.isNotEmpty)
          _sec(t('按天花费'), [
            ...stats.days.reversed.take(7).map((k) {
              final d = stats.day(k);
              final c = PriceCatalog.costOf(
                prompt: d.prompt,
                completion: d.completion,
                inputPerM: s.priceInPerM,
                outputPerM: s.priceOutPerM,
                cachedTokens: d.cached.toDouble(),
                cachedPerM: s.priceInPerM * 0.5,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(_day(k), style: ts(dark, size: 12.5))),
                    Text('${_compact(d.total)} tok',
                        style: meta(dark, size: 11)),
                    const SizedBox(width: 12),
                    Text('¥ ${c.toStringAsFixed(4)}',
                        style: ts(dark, size: 12.5, weight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ]),
      ],
    );
  }

  Future<void> _edit(String title, double current,
      void Function(double value) onSave) async {
    final ctrl = TextEditingController(
        text: current == 0 ? '' : current.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: t('填 0 表示不计算'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          TextButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(t('保存')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) onSave(v < 0 ? 0 : v);
  }

  Widget _row(String label, String value, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(child: Text(label, style: ts(dark, size: 13))),
              Text(value, style: sub(dark, size: 12)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: dark ? C.dInk3 : C.ink3),
            ],
          ),
        ),
      );

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(label, style: meta(dark, size: 11.5))),
            Expanded(child: Text(value, style: ts(dark, size: 12))),
          ],
        ),
      );

  Widget _note(String text) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: sinkOf(dark),
          borderRadius: BorderRadius.circular(D.r),
        ),
        child: Text(text, style: meta(dark, size: 11.5, height: 1.55)),
      );

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${p(d.month)}/${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  String _day(int k) {
    final s = k.toString();
    return s.length == 8
        ? '${s.substring(0, 4)}/${s.substring(4, 6)}/${s.substring(6, 8)}'
        : s;
  }

  static String _compact(int v) {
    if (v < 10000) return '$v';
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '${(v / 1000000).toStringAsFixed(2)}M';
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
        decoration: BoxDecoration(
          color: fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: meta(dark, size: 10.5)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(dark, size: 14, weight: FontWeight.w600)),
          ],
        ),
      );

  Widget _sec(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: surfaceBox(dark, shadowScale: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: ts(dark, size: 14.5, weight: FontWeight.w600)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
}
