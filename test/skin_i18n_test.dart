import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_agent_app/i18n.dart';
import 'package:ai_agent_app/skin.dart';
import 'package:ai_agent_app/theme.dart';
import 'package:ai_agent_app/ui/settings_screen.dart';

void main() {
  group('v4.15 界面语言', () {
    tearDown(() => L10n.useTable('zh', const {}));

    Map<String, String> tsv(String code) => L10n.parseTsv(
        File('assets/i18n/$code.tsv').readAsStringSync());

    test('中文是原文，不做任何替换', () {
      L10n.lang = 'zh';
      expect(t('复制'), '复制');
      expect(t('连接与模型'), '连接与模型');
    });

    test('切到英文后，界面词条全部变英文', () {
      L10n.lang = 'en';
      expect(t('复制'), 'Copy');
      expect(t('发送'), 'Send');
      expect(t('外观主题'), 'Appearance');
      expect(t('设置'), 'Settings');
    });

    test('英文缺词条时回退原文，而不是露 key', () {
      L10n.lang = 'en';
      // 这条故意不在词表里：宁可看到一句中文，也不显示 raw key。
      expect(t('这是一条不存在的词条'), '这是一条不存在的词条');
    });

    test('繁体中文按台湾用语转换', () {
      L10n.useTable('zh-TW', tsv('zh-TW'));
      expect(t('复制'), '複製');
      expect(t('保存'), '儲存');
      expect(t('删除'), '刪除');
    });

    test('日文词表覆盖全部可见文案，不剩中文', () {
      L10n.useTable('ja', tsv('ja'));
      expect(t('发送'), '送信');
      expect(t('取消'), 'キャンセル');
      // 日文本身也用汉字（「例」「設定」），不能靠「不含 CJK」判断，
      // 只能确认它已经不是原来那串中文。
      for (final k in ['按路径筛选，如 app_state / AndroidManifest', '连接与模型', '外观主题']) {
        expect(t(k), isNot(k), reason: '「$k」日文缺失');
      }
    });

    test('设置分类标题跟随界面语言重算，不缓存旧文字', () {
      L10n.lang = 'zh';
      expect(kSettingsCats.first.title, '连接与模型');
      L10n.lang = 'en';
      expect(kSettingsCats.first.title, 'Connection & models');
      expect(kSettingsCats.first.desc, contains('Endpoint'));
    });

    test('语言表里每个界面语言都有本地写法', () {
      expect(kUiLangs.length, greaterThanOrEqualTo(30));
      for (final l in kUiLangs) {
        expect(l.code.trim(), isNotEmpty);
        expect(l.native.trim(), isNotEmpty);
      }
    });

    test('列表里的每种语言都真的有词表，不摆假选项', () {
      var covered = 0;
      for (final l in kUiLangs) {
        if (l.code == 'zh' || l.code == 'en') continue;
        final f = File('assets/i18n/${l.code}.tsv');
        expect(f.existsSync(), isTrue, reason: '${l.code} 列在语言表里却没有词表');
        final rows = L10n.parseTsv(f.readAsStringSync());
        expect(rows.length, greaterThanOrEqualTo(280),
            reason: '${l.code} 词条只有 ${rows.length} 条');
        covered++;
      }
      expect(covered, greaterThanOrEqualTo(30));
    });
  });

  group('v4.15 主题皮肤', () {
    tearDown(() => applySkinFromSettings(
          id: 'github',
          accent: '',
          canvas: '',
          radius: 1.0,
        ));

    test('换主题后语义色跟着换', () {
      applySkinFromSettings(
          id: 'github', accent: '', canvas: '', radius: 1.0);
      final ghSurface = C.surface;
      final ghInk = C.ink;

      applySkinFromSettings(
          id: 'dracula', accent: '', canvas: '', radius: 1.0);
      expect(C.surface, isNot(ghSurface));
      // 墨色统一由明暗决定，主题换的是画布与纸面；
      // 这里用 ink 做对照，确认它没有被主题误伤。
      expect(C.ink, ghInk);
      expect(Skin.preset.name, 'Dracula');
    });

    test('圆角强度只改圆角，不改颜色', () {
      applySkinFromSettings(
          id: 'nord', accent: '', canvas: '', radius: 0.6);
      final tight = D.r;
      final color = C.brand;
      applySkinFromSettings(
          id: 'nord', accent: '', canvas: '', radius: 1.4);
      expect(D.r, greaterThan(tight));
      expect(C.brand, color);
    });

    test('自定义主色与页面底色生效', () {
      applySkinFromSettings(
        id: 'custom',
        accent: '#17A34A',
        canvas: '#FAF9F5',
        radius: 1.0,
      );
      expect(C.brand, const Color(0xFF17A34A));
      expect(C.bg, const Color(0xFFFAF9F5));
      // 纸面要比画布亮，否则卡片浮不起来。
      expect(C.surface.computeLuminance(),
          greaterThan(C.bg.computeLuminance()));
    });

    test('无效色值回退默认，不把界面刷成透明', () {
      applySkinFromSettings(
        id: 'custom',
        accent: 'not-a-color',
        canvas: '',
        radius: 1.0,
      );
      expect(C.brand, const Color(0xFF3478F6));
    });

    test('十八套内置主题都提供了亮暗两套完整色板', () {
      expect(kSkinPresets.length, greaterThanOrEqualTo(18));
      for (final p in kSkinPresets) {
        // 强调色允许亮暗共用（ChatGPT 就是一支绿），
        // 但画布与纸面必须分开，否则深浅色模式会糊成一片。
        expect(p.light.surface, isNot(p.dark.surface));
        expect(p.light.bg, isNot(p.dark.bg));
      }
    });
  });
}
