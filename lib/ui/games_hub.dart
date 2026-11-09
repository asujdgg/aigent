import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/mini_games.dart';
import '../theme.dart';
import 'feature_kit.dart';
import 'life_screen.dart';
import 'mini_game_screen.dart';
import 'roundtable_screen.dart';

/// 设置 → 游戏 的集合页内容。
///
/// 本身不带 Scaffold：作为设置分类子页的 body 嵌入，避免多套一层画布，
/// 也不会出现「框中套框」。每个入口都是独立路由，返回时逐层递减。
class GamesHub extends StatelessWidget {
  const GamesHub({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, t('AI 玩法'), [
          _entry(
            context,
            icon: Icons.forum_rounded,
            title: t('AI 圆桌会议'),
            desc: t('选 3~5 个不同运营商的模型，按大纲多轮讨论并汇总结论'),
            page: const RoundtableScreen(),
            badge: t('多模型'),
          ),
          _entry(
            context,
            icon: Icons.auto_stories_rounded,
            title: t('模拟人生'),
            desc: t('创建角色，由 AI 生成事件与抉择，走完一生'),
            page: const LifeScreen(),
          ),
          _entry(
            context,
            icon: Icons.question_answer_rounded,
            title: t('二十问'),
            desc: t('模型想一个东西，你用是非题在 20 次内猜中'),
            page: const MiniGameScreen(kind: MiniGameKind.twentyQuestions),
            badge: t('AI'),
          ),
          _entry(
            context,
            icon: Icons.menu_book_rounded,
            title: t('故事接龙'),
            desc: t('你一句我一句，让故事一直讲下去'),
            page: const MiniGameScreen(kind: MiniGameKind.storyChain),
            badge: t('AI'),
          ),
        ]),
        const SizedBox(height: 18),
        _section(context, t('离线小游戏'), [
          _entry(
            context,
            icon: Icons.casino_rounded,
            title: t('抉择轮盘'),
            desc: t('把纠结的选项写进去，让轮盘替你决定'),
            page: const MiniGameScreen(kind: MiniGameKind.wheel),
          ),
          _entry(
            context,
            icon: Icons.pin_rounded,
            title: t('猜数字'),
            desc: t('1 到 100，看你能几次猜中'),
            page: const MiniGameScreen(kind: MiniGameKind.guess),
          ),
          _entry(
            context,
            icon: Icons.back_hand_rounded,
            title: t('石头剪刀布'),
            desc: t('来几局，纯靠运气'),
            page: const MiniGameScreen(kind: MiniGameKind.rps),
          ),
          _entry(
            context,
            icon: Icons.auto_awesome_rounded,
            title: t('每日一签'),
            desc: t('每天一支签，图个乐子'),
            page: const MiniGameScreen(kind: MiniGameKind.fortune),
          ),
          _entry(
            context,
            icon: Icons.help_outline_rounded,
            title: t('魔法八球'),
            desc: t('默念一个问题，摇一摇看它怎么答'),
            page: const MiniGameScreen(kind: MiniGameKind.eightBall),
          ),
        ]),
        const SizedBox(height: 6),
        featureHint(
            dark, t('离线小游戏不调用模型、不花流量；AI 玩法按你选的模型计费。')),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(title, style: sectionTitle(dark)),
        ),
        Container(
          decoration: surfaceBox(dark, shadowScale: 0.5),
          clipBehavior: Clip.antiAlias,
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required Widget page,
    String? badge,
  }) {
    final muted = dark ? C.dInk3 : C.ink3;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        SoftPageRoute(
          keepBelow: true,
          builder: (_) => page,
        ),
      ),
      splashColor: (dark ? Colors.white : Colors.black).withOpacity(0.03),
      highlightColor: Colors.transparent,
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: C.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: C.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts(dark,
                                  size: 13.5, weight: FontWeight.w600)),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: C.brand.withOpacity(0.11),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badge,
                                style: ts(dark, size: 9.5, color: C.brand)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
