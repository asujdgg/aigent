import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'life_sim.dart';
import 'roundtable.dart';

/// 新功能（圆桌会议 / 模拟人生）的本地存档。
///
/// 与会话历史分开存：历史文件可能有几 MB，每次进游戏都整份读写太重；
/// 这里只存几十 KB 的 JSON，且用 SharedPreferences 的原子写入。
/// 测试可注入一个内存 Map，不依赖 Flutter 插件通道。
class FeatureStore {
  FeatureStore({Map<String, String>? memory}) : _memory = memory;

  final Map<String, String>? _memory;

  static const String _kMeetings = 'feature.meetings.v1';
  static const String _kLives = 'feature.lives.v1';
  static const String _kSeats = 'feature.seats.v1';

  /// 会议记录与人生存档各留最近 30 份，避免无限膨胀。
  static const int _limit = 30;

  Future<String?> _read(String key) async {
    final m = _memory;
    if (m != null) return m[key];
    return (await SharedPreferences.getInstance()).getString(key);
  }

  Future<void> _write(String key, String value) async {
    final m = _memory;
    if (m != null) {
      m[key] = value;
      return;
    }
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {
      // 存档损坏时当作空，不让页面起不来。
    }
    return <Map<String, dynamic>>[];
  }

  Future<String> _encode(List<Map<String, dynamic>> list) async =>
      jsonEncode(list.take(_limit).toList());

  // ------------------------------------------------------------------ 会议

  Future<List<Meeting>> loadMeetings() async {
    final list = _decode(await _read(_kMeetings));
    return [for (final m in list) Meeting.fromJson(m)];
  }

  Future<void> saveMeetings(List<Meeting> all) async {
    await _write(_kMeetings, await _encode([for (final m in all) m.toJson()]));
  }

  /// 新建或更新一场会议：同 id 覆盖，按时间倒序。
  Future<List<Meeting>> upsertMeeting(Meeting m) async {
    final all = await loadMeetings();
    all.removeWhere((x) => x.id == m.id);
    all.insert(0, m);
    await saveMeetings(all);
    return all;
  }

  Future<void> deleteMeeting(String id) async {
    final all = await loadMeetings();
    all.removeWhere((x) => x.id == id);
    await saveMeetings(all);
  }

  // -------------------------------------------------------------- 人生存档

  Future<List<LifeCharacter>> loadLives() async {
    final list = _decode(await _read(_kLives));
    return [for (final m in list) LifeCharacter.fromJson(m)];
  }

  Future<void> saveLives(List<LifeCharacter> all) async {
    await _write(_kLives, await _encode([for (final c in all) c.toJson()]));
  }

  Future<List<LifeCharacter>> upsertLife(LifeCharacter c) async {
    final all = await loadLives();
    all.removeWhere((x) => x.id == c.id);
    all.insert(0, c);
    await saveLives(all);
    return all;
  }

  Future<void> deleteLife(String id) async {
    final all = await loadLives();
    all.removeWhere((x) => x.id == id);
    await saveLives(all);
  }

  // -------------------------------------------------------------- 席位模板

  Future<List<Seat>> loadSeats() async {
    final list = _decode(await _read(_kSeats));
    return [for (final m in list) Seat.fromJson(m)];
  }

  Future<void> saveSeats(List<Seat> seats) async {
    await _write(_kSeats, jsonEncode([for (final s in seats) s.toJson()]));
  }
}
