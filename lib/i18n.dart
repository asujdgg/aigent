import 'package:flutter/services.dart' show rootBundle;

import 'i18n/en.dart';

/// 界面语言：和「回答语言」「识别语言」是三条独立设置。
///
/// 有人希望界面是英文、答案用中文；也有人反过来。绑在一起会让其中一边
/// 被迫接受不想要的结果，所以这里单独存一个 uiLang。
class UiLang {
  final String code;
  final String name; // 中文名，便于在中文界面里找
  final String native; // 本地写法

  const UiLang(this.code, this.name, this.native);
}

/// 支持完整界面翻译的语言。
///
/// 这份清单必须与 `assets/i18n/*.tsv` 一一对应：列表里出现的语言，
/// 界面就真的整站换成它；没有词表的语言不列进来，避免「切了个假语言」。
const List<UiLang> kUiLangs = [
  UiLang('zh', '简体中文', '简体中文'),
  UiLang('zh-TW', '繁體中文', '繁體中文'),
  UiLang('en', '英语', 'English'),
  UiLang('ja', '日语', '日本語'),
  UiLang('ko', '韩语', '한국어'),
  UiLang('fr', '法语', 'Français'),
  UiLang('de', '德语', 'Deutsch'),
  UiLang('es', '西班牙语', 'Español'),
  UiLang('pt', '葡萄牙语', 'Português'),
  UiLang('ru', '俄语', 'Русский'),
  UiLang('it', '意大利语', 'Italiano'),
  UiLang('nl', '荷兰语', 'Nederlands'),
  UiLang('pl', '波兰语', 'Polski'),
  UiLang('tr', '土耳其语', 'Türkçe'),
  UiLang('uk', '乌克兰语', 'Українська'),
  UiLang('vi', '越南语', 'Tiếng Việt'),
  UiLang('th', '泰语', 'ไทย'),
  UiLang('id', '印尼语', 'Bahasa Indonesia'),
  UiLang('ms', '马来语', 'Bahasa Melayu'),
  UiLang('ar', '阿拉伯语', 'العربية'),
  UiLang('hi', '印地语', 'हिन्दी'),
  UiLang('bn', '孟加拉语', 'বাংলা'),
  UiLang('cs', '捷克语', 'Čeština'),
  UiLang('sv', '瑞典语', 'Svenska'),
  UiLang('da', '丹麦语', 'Dansk'),
  UiLang('fi', '芬兰语', 'Suomi'),
  UiLang('nb', '挪威语', 'Norsk'),
  UiLang('el', '希腊语', 'Ελληνικά'),
  UiLang('he', '希伯来语', 'עברית'),
  UiLang('ro', '罗马尼亚语', 'Română'),
  UiLang('hu', '匈牙利语', 'Magyar'),
  UiLang('sk', '斯洛伐克语', 'Slovenčina'),
  UiLang('bg', '保加利亚语', 'Български'),
  UiLang('fa', '波斯语', 'فارسی'),
  UiLang('ur', '乌尔都语', 'اردو'),
  UiLang('ca', '加泰罗尼亚语', 'Català'),
  UiLang('et', '爱沙尼亚语', 'Eesti'),
  UiLang('lt', '立陶宛语', 'Lietuvių'),
  UiLang('lv', '拉脱维亚语', 'Latviešu'),
  UiLang('sw', '斯瓦希里语', 'Kiswahili'),
];

/// 查表：当前语言 → 英文 → 中文原文。
///
/// 词表以中文原文为 key，而不是发明一套 `settings.appearance.fontSize`
/// 之类的路径：代码里读起来就是正常句子，漏翻时也不会显示一串 key。
///
/// 30 多种语言 × 300 条如果全编译进 Dart，会让 `const` 表膨胀到几百 KB、
/// 每次改动都重编译整个 app；所以除中文和英文外，词表放在
/// `assets/i18n/<code>.tsv`，切换语言时读一次（几毫秒），之后同步查表。
class L10n {
  static String lang = 'zh';
  static Map<String, String> _table = const {};

  /// 切换语言并载入词表。切换前必须 await，否则首帧会先显示英文。
  static Future<void> load(String code) async {
    lang = code;
    _table = const {};
    if (code == 'zh') return;
    try {
      final raw = await rootBundle.loadString('assets/i18n/$code.tsv');
      _table = parseTsv(raw);
    } catch (_) {
      // 资源缺失时按「英文 → 中文」回退，界面不会崩。
    }
  }

  /// TSV：`中文原文\t译文`，一行一条。用制表符而不是 JSON，
  /// 体积小一半，diff 也可读。
  static Map<String, String> parseTsv(String raw) {
    final out = <String, String>{};
    for (final line in raw.split('\n')) {
      if (line.isEmpty) continue;
      final i = line.indexOf('\t');
      if (i <= 0) continue;
      final k = line.substring(0, i).replaceAll(r'\n', '\n');
      final v = line.substring(i + 1).replaceAll(r'\n', '\n');
      if (v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  static String t(String zh) {
    if (lang == 'zh') return zh;
    final hit = _table[zh];
    if (hit != null) return hit;
    final en = kEnUi[zh];
    if (en != null) return en;
    return zh;
  }

  /// 直接注入词表：单测里不想依赖 asset bundle，也方便将来做热更新。
  static void useTable(String code, Map<String, String> table) {
    lang = code;
    _table = table;
  }

  static bool get isZh => lang == 'zh' || lang == 'zh-TW';

  /// 当前语言是否已载入词表（设置页用来提示「正在切换」）。
  static bool get ready => lang == 'zh' || _table.isNotEmpty;
}

String t(String zh) => L10n.t(zh);

/// 语言显示名。界面已经是英文时，别在语言列表里继续用中文名。
String uiLangLabel(UiLang l) => l.native;

UiLang? uiLangByCode(String code) {
  for (final l in kUiLangs) {
    if (l.code == code) return l;
  }
  return null;
}
