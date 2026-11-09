import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../services/feature_store.dart';
import '../services/model_source.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'feature_kit.dart';
import 'provider_model_picker.dart';

/// 游戏页共用的「当前模型」条：一眼看清这一局用的是哪家、哪个模型，
/// 点一下走两级选择器切换，也可以恢复成「跟随当前对话」。
///
/// 偏好只存地址与模型名，密钥按地址从当前连接补，绝不落盘。
class GameModelBar extends StatefulWidget {
  const GameModelBar({
    super.key,
    required this.dark,
    required this.store,
    this.onChanged,
  });

  final bool dark;
  final FeatureStore store;
  final ValueChanged<ModelChoice>? onChanged;

  @override
  State<GameModelBar> createState() => GameModelBarState();
}

class GameModelBarState extends State<GameModelBar> {
  GameModelPref? _pref;
  bool _booted = false;

  AppState get st => Provider.of<AppState>(context, listen: false);

  /// 当前生效的连接（已经补好密钥），引擎直接拿它发请求。
  ModelChoice get choice => resolveModelChoice(
        st.settings,
        baseUrl: _pref?.baseUrl,
        model: _pref?.model,
        providerName: _pref?.providerName,
      );

  bool get usingDefault => _pref == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    GameModelPref? p;
    try {
      p = await widget.store.loadGameModel();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pref = p;
      _booted = true;
    });
    widget.onChanged?.call(choice);
  }

  Future<void> pick() async {
    final c = choice;
    final picked = await showProviderModelPicker(
      context,
      dark: widget.dark,
      currentBaseUrl: c.baseUrl,
      currentModel: c.model,
      title: t('选择游戏模型'),
    );
    if (picked == null || !mounted) return;
    final p = GameModelPref(
      baseUrl: picked.baseUrl,
      model: picked.model,
      providerName: picked.providerName,
    );
    await widget.store.saveGameModel(p);
    if (!mounted) return;
    setState(() => _pref = p);
    widget.onChanged?.call(choice);
  }

  Future<void> useDefault() async {
    await widget.store.saveGameModel(const GameModelPref(
      baseUrl: '',
      model: '',
      providerName: '',
    ));
    if (!mounted) return;
    setState(() => _pref = null);
    widget.onChanged?.call(choice);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final c = choice;
    final ready = _booted;
    return featureCard(dark, [
      Row(
        children: [
          Expanded(child: featureLabel(dark, t('本局使用的模型'))),
          if (!usingDefault)
            GestureDetector(
              onTap: useDefault,
              child: Text(t('恢复默认'),
                  style: ts(dark, size: 11, color: accentOf(dark))),
            ),
        ],
      ),
      InkWell(
        borderRadius: BorderRadius.circular(D.r),
        onTap: ready ? pick : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fieldOf(dark),
            borderRadius: BorderRadius.circular(D.r),
            border: Border.all(color: hairOf(dark), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 18, color: accentOf(dark)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.providerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(dark,
                            size: 12.5, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(c.model.trim().isEmpty ? t('未设置模型') : c.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta(dark, size: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: dark ? C.dInk3 : C.ink3),
            ],
          ),
        ),
      ),
      featureHint(
          dark,
          usingDefault
              ? t('默认跟随当前对话的模型；点这里可为游戏单独指定。')
              : t('已为游戏单独指定模型，随时可换或恢复默认。')),
    ]);
  }
}
