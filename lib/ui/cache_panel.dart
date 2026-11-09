import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../services/cache_store.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 设置 → 缓存命中：既能看统计，也能改开关、清缓存。
///
/// 数据来自两个真实来源，不会凭空造数字：
/// - 服务端提示词缓存命中（网关 usage 里的 cached_tokens）；
/// - 本地响应复用（完全相同的非流式请求直接返回上次回答）。
class CachePanel extends StatelessWidget {
  const CachePanel({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final l = st.cacheLedger;
    final saving = st.cacheSaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sec(t('命中概览'), [
          Row(
            children: [
              Expanded(child: _stat(t('命中次数'), '${l.hits}')),
              const SizedBox(width: 8),
              Expanded(child: _stat(t('缓存 token'), _compact(l.tokens))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _stat(t('估算省下'),
                      saving > 0 ? '¥ ${saving.toStringAsFixed(3)}' : '—')),
              const SizedBox(width: 8),
              Expanded(child: _stat(t('缓存条目'), '${st.responseCache.size}')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${t('服务端缓存命中')} ${l.promptHits} ${t('次')} · '
            '${_compact(l.promptTokens)} tok　|　'
            '${t('本地复用')} ${l.responseHits} ${t('次')} · '
            '${_compact(l.responseTokens)} tok',
            style: meta(dark, size: 11.5, height: 1.5),
          ),
        ]),

        _sec(t('缓存设置'), [
          SwitchRow(
            title: t('复用相同请求的回答'),
            subtitle: t('圆桌会议、模拟人生、小游戏与深度研究里完全相同的请求，6 小时内直接复用上次结果，不再发起请求也不计费。主对话是流式的，永远拿新回答。'),
            value: st.settings.responseCacheEnabled,
            icon: Icons.cached_rounded,
            onChanged: (v) => st.patch((x) => x.responseCacheEnabled = v),
          ),
          const SizedBox(height: 8),
          _note(t('两种命中都会被记录：服务端返回的提示词缓存 token 只按折扣计价；本地复用则连请求都不发。省钱金额按你当前填写的输入单价估算，不是账单。')),
        ]),

        _sec(t('最近命中'), [
          if (l.records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(t('还没有命中记录。用一会儿圆桌会议或小游戏，这里就会有数据。'),
                  style: sub(dark, size: 12.5)),
            )
          else
            ...l.records.take(30).map((e) => _record(e)),
          if (l.records.length > 30)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('${t('仅显示最近 30 条')} · ${t('共')} ${l.records.length} ${t('条')}',
                  style: meta(dark, size: 11)),
            ),
        ]),

        _sec(t('管理'), [
          Row(
            children: [
              Expanded(
                child: _btn(t('清空命中记录'), () => _confirmClear(
                      context,
                      t('清空命中记录？'),
                      t('只清统计与列表，不影响已缓存的回答。'),
                      st.clearCacheRecords,
                    )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn(t('清空响应缓存'), () => _confirmClear(
                      context,
                      t('清空响应缓存？'),
                      t('之后相同的请求会重新发起，直到再次被缓存。'),
                      st.clearResponseCache,
                    ), danger: true),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, String title, String body,
      Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('清空'))),
        ],
      ),
    );
    if (ok == true) await run();
  }

  Widget _record(CacheHitEntry e) {
    final local = e.kind == CacheHitKind.response;
    final d = DateTime.fromMillisecondsSinceEpoch(e.at);
    String p(int v) => v.toString().padLeft(2, '0');
    final time = '${d.month}/${d.day} ${p(d.hour)}:${p(d.minute)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: lineOf(dark), width: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (local ? C.ok : C.brand).withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(local ? t('本地复用') : t('服务端缓存'),
                style: ts(dark, size: 10, weight: FontWeight.w600,
                    color: local ? C.ok : accentOf(dark))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.summary.isEmpty ? e.model : e.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(dark, size: 12.5)),
                const SizedBox(height: 2),
                Text('$time · ${e.model} · ${_compact(e.tokens)} tok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta(dark, size: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _compact(int v) {
    if (v < 10000) return '$v';
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '${(v / 1000000).toStringAsFixed(2)}M';
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: fieldOf(dark),
          borderRadius: BorderRadius.circular(D.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: meta(dark, size: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: ts(dark, size: 18, weight: FontWeight.w600)),
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

  Widget _btn(String label, VoidCallback onTap, {bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fieldOf(dark),
            borderRadius: BorderRadius.circular(D.r),
            border: Border.all(color: borderOf(dark), width: 0.8),
          ),
          child: Text(label,
              style: ts(dark,
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: danger ? C.warn : accentOf(dark))),
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
