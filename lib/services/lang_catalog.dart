/// 语言目录：对话语言（AI 用什么语言回答）与语音识别语言。
///
/// 两套编码不能混用：
/// - 对话语言只取一段给模型看的名字（写进 System Prompt），用 `code` 做持久化；
/// - 识别语言必须是 BCP-47（`zh-CN` / `en-US`），Whisper 只取第一段。
///
/// 列表覆盖世界主流语言 + 常见小语种，纯数据、可单测。
library;

import '../i18n.dart';

class AppLang {
  /// 持久化用的稳定标识（对话语言）。
  final String code;

  /// 中文名，设置页里给人看。
  final String label;

  /// 该语言自己的写法，列表里做副标题。
  final String native;

  /// 写进 System Prompt 的名字（英文名最不容易被模型误解）。
  final String prompt;

  const AppLang(this.code, this.label, this.native, this.prompt);
}

/// 对话语言。`auto` 表示跟随用户提问语言。
const List<AppLang> kReplyLangs = [
  AppLang('auto', '跟随提问', 'Auto', ''),
  AppLang('zh-Hans', '简体中文', '简体中文', 'Simplified Chinese'),
  AppLang('zh-Hant', '繁体中文', '繁體中文', 'Traditional Chinese'),
  AppLang('en', '英语', 'English', 'English'),
  AppLang('ja', '日语', '日本語', 'Japanese'),
  AppLang('ko', '韩语', '한국어', 'Korean'),
  AppLang('es', '西班牙语', 'Español', 'Spanish'),
  AppLang('fr', '法语', 'Français', 'French'),
  AppLang('de', '德语', 'Deutsch', 'German'),
  AppLang('pt', '葡萄牙语', 'Português', 'Portuguese'),
  AppLang('ru', '俄语', 'Русский', 'Russian'),
  AppLang('ar', '阿拉伯语', 'العربية', 'Arabic'),
  AppLang('hi', '印地语', 'हिन्दी', 'Hindi'),
  AppLang('it', '意大利语', 'Italiano', 'Italian'),
  AppLang('nl', '荷兰语', 'Nederlands', 'Dutch'),
  AppLang('pl', '波兰语', 'Polski', 'Polish'),
  AppLang('tr', '土耳其语', 'Türkçe', 'Turkish'),
  AppLang('sv', '瑞典语', 'Svenska', 'Swedish'),
  AppLang('no', '挪威语', 'Norsk', 'Norwegian'),
  AppLang('da', '丹麦语', 'Dansk', 'Danish'),
  AppLang('fi', '芬兰语', 'Suomi', 'Finnish'),
  AppLang('cs', '捷克语', 'Čeština', 'Czech'),
  AppLang('sk', '斯洛伐克语', 'Slovenčina', 'Slovak'),
  AppLang('hu', '匈牙利语', 'Magyar', 'Hungarian'),
  AppLang('ro', '罗马尼亚语', 'Română', 'Romanian'),
  AppLang('bg', '保加利亚语', 'Български', 'Bulgarian'),
  AppLang('el', '希腊语', 'Ελληνικά', 'Greek'),
  AppLang('he', '希伯来语', 'עברית', 'Hebrew'),
  AppLang('fa', '波斯语', 'فارسی', 'Persian'),
  AppLang('ur', '乌尔都语', 'اردو', 'Urdu'),
  AppLang('th', '泰语', 'ไทย', 'Thai'),
  AppLang('vi', '越南语', 'Tiếng Việt', 'Vietnamese'),
  AppLang('id', '印尼语', 'Bahasa Indonesia', 'Indonesian'),
  AppLang('ms', '马来语', 'Bahasa Melayu', 'Malay'),
  AppLang('fil', '菲律宾语', 'Filipino', 'Filipino'),
  AppLang('uk', '乌克兰语', 'Українська', 'Ukrainian'),
  AppLang('sr', '塞尔维亚语', 'Српски', 'Serbian'),
  AppLang('hr', '克罗地亚语', 'Hrvatski', 'Croatian'),
  AppLang('sl', '斯洛文尼亚语', 'Slovenščina', 'Slovenian'),
  AppLang('et', '爱沙尼亚语', 'Eesti', 'Estonian'),
  AppLang('lv', '拉脱维亚语', 'Latviešu', 'Latvian'),
  AppLang('lt', '立陶宛语', 'Lietuvių', 'Lithuanian'),
  AppLang('is', '冰岛语', 'Íslenska', 'Icelandic'),
  AppLang('ga', '爱尔兰语', 'Gaeilge', 'Irish'),
  AppLang('cy', '威尔士语', 'Cymraeg', 'Welsh'),
  AppLang('ca', '加泰罗尼亚语', 'Català', 'Catalan'),
  AppLang('eu', '巴斯克语', 'Euskara', 'Basque'),
  AppLang('bn', '孟加拉语', 'বাংলা', 'Bengali'),
  AppLang('ta', '泰米尔语', 'தமிழ்', 'Tamil'),
  AppLang('te', '泰卢固语', 'తెలుగు', 'Telugu'),
  AppLang('mr', '马拉地语', 'मराठी', 'Marathi'),
  AppLang('gu', '古吉拉特语', 'ગુજરાતી', 'Gujarati'),
  AppLang('pa', '旁遮普语', 'ਪੰਜਾਬੀ', 'Punjabi'),
  AppLang('ne', '尼泊尔语', 'नेपाली', 'Nepali'),
  AppLang('si', '僧伽罗语', 'සිංහල', 'Sinhala'),
  AppLang('my', '缅甸语', 'မြန်မာ', 'Burmese'),
  AppLang('km', '高棉语', 'ខ្មែរ', 'Khmer'),
  AppLang('lo', '老挝语', 'ລາວ', 'Lao'),
  AppLang('mn', '蒙古语', 'Монгол', 'Mongolian'),
  AppLang('kk', '哈萨克语', 'Қазақша', 'Kazakh'),
  AppLang('uz', '乌兹别克语', 'Oʻzbekcha', 'Uzbek'),
  AppLang('az', '阿塞拜疆语', 'Azərbaycanca', 'Azerbaijani'),
  AppLang('hy', '亚美尼亚语', 'Հայերեն', 'Armenian'),
  AppLang('ka', '格鲁吉亚语', 'ქართული', 'Georgian'),
  AppLang('sw', '斯瓦希里语', 'Kiswahili', 'Swahili'),
  AppLang('am', '阿姆哈拉语', 'አማርኛ', 'Amharic'),
  AppLang('ha', '豪萨语', 'Hausa', 'Hausa'),
  AppLang('yo', '约鲁巴语', 'Yorùbá', 'Yoruba'),
  AppLang('ig', '伊博语', 'Igbo', 'Igbo'),
  AppLang('zu', '祖鲁语', 'isiZulu', 'Zulu'),
  AppLang('af', '南非荷兰语', 'Afrikaans', 'Afrikaans'),
  AppLang('eo', '世界语', 'Esperanto', 'Esperanto'),
  AppLang('la', '拉丁语', 'Latina', 'Latin'),
];

AppLang? replyLangByCode(String code) {
  for (final l in kReplyLangs) {
    if (l.code == code) return l;
  }
  return null;
}

/// 写进 System Prompt 的语言名；`auto` 或未知返回空串（不追加指令）。
String replyLangPrompt(String code) => replyLangByCode(code)?.prompt ?? '';

String replyLangLabel(String code) {
  final l = replyLangByCode(code);
  if (l == null) return t('跟随提问');
  // 界面已经是外语时，摘要里再出现「英语 / 日语」这种中文名很突兀，
  // 改用该语言自己的写法（English / 日本語）。
  return L10n.isZh ? l.label : l.native;
}

/// 语音识别语言（BCP-47）。Whisper 只取第一段，所以 `zh-CN` 与 `zh` 等价。
class SpeechLang {
  final String code;
  final String label;
  final String native;
  const SpeechLang(this.code, this.label, this.native);
}

const List<SpeechLang> kSpeechLangs = [
  SpeechLang('zh-CN', '中文（普通话）', '简体中文'),
  SpeechLang('zh-HK', '中文（粤语）', '廣東話'),
  SpeechLang('zh-TW', '中文（台湾）', '繁體中文'),
  SpeechLang('en-US', '英语（美）', 'English (US)'),
  SpeechLang('en-GB', '英语（英）', 'English (UK)'),
  SpeechLang('ja-JP', '日语', '日本語'),
  SpeechLang('ko-KR', '韩语', '한국어'),
  SpeechLang('es-ES', '西班牙语', 'Español'),
  SpeechLang('fr-FR', '法语', 'Français'),
  SpeechLang('de-DE', '德语', 'Deutsch'),
  SpeechLang('pt-BR', '葡萄牙语（巴）', 'Português (BR)'),
  SpeechLang('ru-RU', '俄语', 'Русский'),
  SpeechLang('ar-SA', '阿拉伯语', 'العربية'),
  SpeechLang('hi-IN', '印地语', 'हिन्दी'),
  SpeechLang('it-IT', '意大利语', 'Italiano'),
  SpeechLang('nl-NL', '荷兰语', 'Nederlands'),
  SpeechLang('pl-PL', '波兰语', 'Polski'),
  SpeechLang('tr-TR', '土耳其语', 'Türkçe'),
  SpeechLang('sv-SE', '瑞典语', 'Svenska'),
  SpeechLang('no-NO', '挪威语', 'Norsk'),
  SpeechLang('da-DK', '丹麦语', 'Dansk'),
  SpeechLang('fi-FI', '芬兰语', 'Suomi'),
  SpeechLang('cs-CZ', '捷克语', 'Čeština'),
  SpeechLang('sk-SK', '斯洛伐克语', 'Slovenčina'),
  SpeechLang('hu-HU', '匈牙利语', 'Magyar'),
  SpeechLang('ro-RO', '罗马尼亚语', 'Română'),
  SpeechLang('bg-BG', '保加利亚语', 'Български'),
  SpeechLang('el-GR', '希腊语', 'Ελληνικά'),
  SpeechLang('he-IL', '希伯来语', 'עברית'),
  SpeechLang('fa-IR', '波斯语', 'فارسی'),
  SpeechLang('ur-PK', '乌尔都语', 'اردو'),
  SpeechLang('th-TH', '泰语', 'ไทย'),
  SpeechLang('vi-VN', '越南语', 'Tiếng Việt'),
  SpeechLang('id-ID', '印尼语', 'Bahasa Indonesia'),
  SpeechLang('ms-MY', '马来语', 'Bahasa Melayu'),
  SpeechLang('fil-PH', '菲律宾语', 'Filipino'),
  SpeechLang('uk-UA', '乌克兰语', 'Українська'),
  SpeechLang('sr-RS', '塞尔维亚语', 'Српски'),
  SpeechLang('hr-HR', '克罗地亚语', 'Hrvatski'),
  SpeechLang('sl-SI', '斯洛文尼亚语', 'Slovenščina'),
  SpeechLang('et-EE', '爱沙尼亚语', 'Eesti'),
  SpeechLang('lv-LV', '拉脱维亚语', 'Latviešu'),
  SpeechLang('lt-LT', '立陶宛语', 'Lietuvių'),
  SpeechLang('is-IS', '冰岛语', 'Íslenska'),
  SpeechLang('ga-IE', '爱尔兰语', 'Gaeilge'),
  SpeechLang('cy-GB', '威尔士语', 'Cymraeg'),
  SpeechLang('ca-ES', '加泰罗尼亚语', 'Català'),
  SpeechLang('bn-BD', '孟加拉语', 'বাংলা'),
  SpeechLang('ta-IN', '泰米尔语', 'தமிழ்'),
  SpeechLang('te-IN', '泰卢固语', 'తెలుగు'),
  SpeechLang('mr-IN', '马拉地语', 'मराठी'),
  SpeechLang('ne-NP', '尼泊尔语', 'नेपाली'),
  SpeechLang('si-LK', '僧伽罗语', 'සිංහල'),
  SpeechLang('my-MM', '缅甸语', 'မြန်မာ'),
  SpeechLang('km-KH', '高棉语', 'ខ្មែរ'),
  SpeechLang('lo-LA', '老挝语', 'ລາວ'),
  SpeechLang('mn-MN', '蒙古语', 'Монгол'),
  SpeechLang('kk-KZ', '哈萨克语', 'Қазақша'),
  SpeechLang('uz-UZ', '乌兹别克语', 'Oʻzbekcha'),
  SpeechLang('sw-KE', '斯瓦希里语', 'Kiswahili'),
  SpeechLang('am-ET', '阿姆哈拉语', 'አማርኛ'),
  SpeechLang('ha-NG', '豪萨语', 'Hausa'),
  SpeechLang('yo-NG', '约鲁巴语', 'Yorùbá'),
  SpeechLang('zu-ZA', '祖鲁语', 'isiZulu'),
  SpeechLang('af-ZA', '南非荷兰语', 'Afrikaans'),
  SpeechLang('eo', '世界语', 'Esperanto'),
];

SpeechLang? speechLangByCode(String code) {
  final c = code.trim();
  if (c.isEmpty) return null;
  for (final l in kSpeechLangs) {
    if (l.code == c) return l;
  }
  // 只写 `zh` / `en` 这种短码时按前缀兜底。
  for (final l in kSpeechLangs) {
    if (l.code.toLowerCase().startsWith(c.toLowerCase())) return l;
  }
  return null;
}

String speechLangLabel(String code) {
  final l = speechLangByCode(code);
  if (l == null) return code.isEmpty ? t('未设置') : code;
  return L10n.isZh ? l.label : l.native;
}

/// 语言设置三档字号（与 AppSettings.fontScale 对应）。
class FontScaleOption {
  final double value;
  final String label;
  const FontScaleOption(this.value, this.label);
}

const List<FontScaleOption> kFontScales = [
  FontScaleOption(0.9, '小'),
  FontScaleOption(1.0, '标准'),
  FontScaleOption(1.12, '大'),
  FontScaleOption(1.25, '特大'),
];

String fontScaleLabel(double v) {
  var best = kFontScales.first;
  for (final o in kFontScales) {
    if ((o.value - v).abs() < (best.value - v).abs()) best = o;
  }
  return best.label;
}
