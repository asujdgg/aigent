import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent_app/models/models.dart';
import 'package:ai_agent_app/services/agent_script.dart';
import 'package:ai_agent_app/services/agent_tools.dart';
import 'package:ai_agent_app/services/agent_workspace.dart';
import 'package:ai_agent_app/services/device_bridge.dart';
import 'package:ai_agent_app/services/speech_model.dart';
import 'package:ai_agent_app/state/app_state.dart';
import 'package:ai_agent_app/ui/source_browser.dart';

late Directory _tmp;
late AgentWorkspace _ws;

Future<void> _fresh() async {
  _tmp = await Directory.systemTemp.createTemp('aigent_ws_test_');
  _ws = AgentWorkspace(_tmp.path);
  await _ws.ensure();
}

void main() {
  setUp(_fresh);
  tearDown(() async {
    if (_tmp.existsSync()) await _tmp.delete(recursive: true);
  });

  group('隔离工作区：路径逃逸必须被拒绝', () {
    test('绝对路径 / 盘符 / .. / 隐藏文件 / 系统保留目录全部拒绝', () async {
      for (final bad in [
        '/etc/passwd',
        'C:/Windows/win.ini',
        '../outside.txt',
        'notes/../../outside.txt',
        '.hidden',
        '.trash/abc',
        'agent_log.jsonl',
        'notes/.secret',
      ]) {
        expect(
          () => _ws.read(bad),
          throwsA(isA<WorkspaceException>()),
          reason: '路径 $bad 不该被放行',
        );
      }
    });

    test('写 / 读 / 追加 / 列目录', () async {
      final a = await _ws.write('notes/a.txt', '第一行');
      expect(a, contains('已写入'));
      expect(await _ws.read('notes/a.txt'), '第一行');
      await _ws.append('notes/a.txt', '，第二行');
      expect(await _ws.read('notes/a.txt'), '第一行，第二行');
      final entries = await _ws.list('notes');
      expect(entries.length, 1);
      expect(entries.first.rel, 'notes/a.txt');
      expect(entries.first.isDir, isFalse);
    });

    test('符号链接指向工作区之外时拒绝读取', () async {
      final outside = File('${_tmp.path}_outside.txt');
      await outside.writeAsString('secret');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete();
      });
      Link('${_tmp.path}/link.txt').createSync(outside.path);
      expect(
        () => _ws.read('link.txt'),
        throwsA(isA<WorkspaceException>()),
      );
    });
  });

  group('隔离工作区：文件永不丢失', () {
    test('覆盖写自动备份旧版，删除进回收站且可恢复回原子目录', () async {
      await _ws.write('notes/a.txt', 'v1');
      await _ws.write('notes/a.txt', 'v2');
      expect(await _ws.read('notes/a.txt'), 'v2');

      var trash = await _ws.trashList();
      expect(trash.length, 1, reason: '覆盖前必须先备份 v1');
      expect(trash.first.name, contains('notes__a.txt'));

      final msg = await _ws.delete('notes/a.txt');
      expect(msg, contains('未真正删除'));
      expect(File('${_tmp.path}/notes/a.txt').existsSync(), isFalse);
      trash = await _ws.trashList();
      expect(trash.length, 2);

      // 恢复最近一次删除，应该回到 notes/ 而不是根目录。
      final restored = await _ws.restore(trash.first.name);
      expect(restored, contains('notes'));
      expect(await _ws.read('notes/a.txt'), 'v2');
      expect(File('${_tmp.path}/a.txt').existsSync(), isFalse);
    });

    test('回收站可永久清空，清空后列表为空', () async {
      await _ws.write('a.txt', 'x');
      await _ws.delete('a.txt');
      expect((await _ws.trashList()).length, 1);
      final msg = await _ws.clearTrash();
      expect(msg, contains('已永久清空'));
      expect(await _ws.trashList(), isEmpty);
    });

    test('单文件超过 2 MB 拒绝写入', () async {
      final big = 'x' * (AgentWorkspace.maxFileBytes + 1);
      expect(
        () => _ws.write('big.txt', big),
        throwsA(isA<WorkspaceException>()),
      );
      expect(File('${_tmp.path}/big.txt').existsSync(), isFalse);
    });

    test('用量统计不含回收站与日志文件', () async {
      await _ws.write('a.txt', 'hello');
      await _ws.write('b.txt', 'world');
      await _ws.delete('b.txt');
      final u = await _ws.usage();
      expect(u.files, 1);
      expect(u.bytes, 5);
      expect(u.trashFiles, 1);
    });
  });

  group('审计日志', () {
    test('每次动作写入 jsonl 并能读回', () async {
      for (var i = 0; i < 3; i++) {
        await _ws.log(AgentLogEntry(
          at: 1700000000000 + i,
          tool: 'agent.workspace.write',
          detail: '第 $i 次写入',
          ok: i != 1,
        ));
      }
      final log = await _ws.readLog();
      expect(log.length, 3);
      expect(log.first.detail, '第 2 次写入', reason: '最新一条排最前');
      expect(log.last.ok, isTrue);
      expect(log[1].ok, isFalse);
    });
  });

  group('受限任务脚本', () {
    test('能写多行文档、追加、读取、列目录并插值变量', () async {
      final r = await AgentScriptRunner(_ws).run('''
# 整理今天的笔记
print 开始整理 \${model}
write notes/plan.md <<<
# 计划
设备 \${model}
>>>
append notes/plan.md 追加一行
read notes/plan.md
list notes
''', deviceModel: 'Pixel 8');
      expect(r.ok, isTrue, reason: r.error ?? r.output);
      expect(r.output, contains('开始整理 Pixel 8'));
      expect(r.output, contains('已写入'));
      expect(await _ws.read('notes/plan.md'), contains('# 计划'));
      expect(await _ws.read('notes/plan.md'), contains('追加一行'));
    });

    test('未知指令与超长脚本都拒绝执行', () async {
      final bad = await AgentScriptRunner(_ws).run('rm -rf /\nprint hi');
      expect(bad.ok, isFalse);
      expect(bad.error, contains('未知指令'));

      final long = await AgentScriptRunner(_ws)
          .run(List.filled(220, 'print x').join('\n'));
      expect(long.ok, isFalse);
      expect(long.error, contains('行上限'));
    });

    test('脚本里的越界路径同样被工作区拦截', () async {
      final r = await AgentScriptRunner(_ws).run('write ../evil.txt hi');
      expect(r.ok, isFalse);
      expect(r.output, anyOf(contains('..'), contains('越出')));
      expect(File('${_tmp.path}_evil.txt').existsSync(), isFalse);
    });
  });

  group('本机工具解析与授权', () {
    test('识别 fenced / 内联 / 裸短名，不误吞插件工具', () {
      final a = parseAgentToolCall(
          '```tool\n{"tool":"agent.app.open","arguments":{"name":"微信"}}\n```');
      expect(a?['tool'], 'agent.app.open');
      expect((a?['arguments'] as Map)['name'], '微信');

      final b = parseAgentToolCall(
          '好的，我来打开\n{"tool":"device.info","arguments":{}}');
      expect(b?['tool'], 'agent.device.info');

      expect(parseAgentToolCall(
          '{"tool":"getWeather","arguments":{"city":"北京"}}'), isNull);
      expect(parseAgentToolCall('只是一段普通回答'), isNull);
    });

    test('工具全集 id 唯一，只读工具无需确认', () {
      final ids = kAgentTools.map((t) => t.id).toSet();
      expect(ids.length, kAgentTools.length);
      expect(kAgentTools.length, greaterThanOrEqualTo(20));
      for (final t in kAgentTools) {
        if (t.risk == AgentRisk.read) {
          expect(t.needsConfirmation, isFalse, reason: t.id);
          expect(t.grant, isEmpty, reason: t.id);
        } else {
          expect(t.needsConfirmation, isTrue, reason: t.id);
          expect(t.grant, isNotEmpty, reason: t.id);
        }
      }
    });

    test('授权快照按组生效，标签可读', () {
      const g = AgentGrant(workspace: true);
      expect(g.allows(''), isTrue);
      expect(g.allows('workspace'), isTrue);
      expect(g.allows('external'), isFalse);
      expect(g.allows('system'), isFalse);
      expect(g.allows('network'), isFalse);
      expect(AgentGrant.labelOf('system'), '日历与闹钟');
    });

    test('未授权动作不执行，返回需要哪一组授权', () async {
      final rt = AgentRuntime(
        workspace: _ws,
        grant: const AgentGrant(),
        deviceInfo: DeviceInfo.fallback(),
        confirmEach: false,
      );
      final e = await rt.execute(
          'agent.workspace.write', {'path': 'a.txt', 'content': 'x'});
      expect(e.ok, isFalse);
      expect(e.missingGrant, 'workspace');
      expect(File('${_tmp.path}/a.txt').existsSync(), isFalse);
      expect(await _ws.readLog(), isNotEmpty, reason: '拒绝也要留痕');
    });

    test('拒绝确认后按「用户拒绝」回灌，不产生副作用', () async {
      final rt = AgentRuntime(
        workspace: _ws,
        grant: const AgentGrant(workspace: true),
        deviceInfo: DeviceInfo.fallback(),
        confirmEach: true,
        confirm: (_) async => false,
      );
      final e = await rt.execute(
          'agent.workspace.write', {'path': 'a.txt', 'content': 'x'});
      expect(e.ok, isFalse);
      expect(e.declined, isTrue);
      expect(e.asToolResult, contains('用户拒绝'));
      expect(File('${_tmp.path}/a.txt').existsSync(), isFalse);
    });

    test('授权 + 允许后真的把文件写进工作区', () async {
      final rt = AgentRuntime(
        workspace: _ws,
        grant: const AgentGrant(workspace: true),
        deviceInfo: DeviceInfo.fallback(),
        confirmEach: true,
        confirm: (_) async => true,
      );
      final e = await rt.execute(
          'agent.workspace.write', {'path': 'result.md', 'content': '# 结果'});
      expect(e.ok, isTrue);
      expect(await _ws.read('result.md'), '# 结果');
      expect(e.asToolResult, contains('[工具 写文件 执行结果]'));
    });

    test('设备信息只读工具始终可用', () async {
      final rt = AgentRuntime(
        workspace: _ws,
        grant: const AgentGrant(),
        deviceInfo: DeviceInfo.fallback(),
        confirmEach: true,
        confirm: (_) async => false,
      );
      final e = await rt.execute('agent.device.info', {});
      expect(e.ok, isTrue);
      expect(e.message, contains('设备'));
    });

    test('内网 / 回环 / 元数据主机被拦，公网域名放行', () {
      for (final h in [
        '127.0.0.1',
        '10.0.0.5',
        '192.168.1.1',
        '172.16.3.4',
        '169.254.169.254',
        'localhost',
        'metadata.google.internal',
        'nas.local',
      ]) {
        expect(AgentRuntime.isBlockedHost(h), isTrue, reason: h);
      }
      for (final h in ['example.com', 'api.openai.com', '93.184.216.34']) {
        expect(AgentRuntime.isBlockedHost(h), isFalse, reason: h);
      }
    });
  });

  group('设备信息兜底与源码包', () {
    test('没有原生通道时仍给出完整设备摘要', () {
      final info = DeviceInfo.fallback();
      expect(info.fromDevice, isFalse);
      expect(info.rows.length, greaterThanOrEqualTo(10));
      expect(info.promptSummary, contains('设备'));
      expect(info.promptSummary, contains('系统'));
    });

    test('源码包解析保留路径、行数与内容', () {
      final bundle = SourceBundle.parse(jsonEncode({
        'version': '4.7.0',
        'generated': '2026-11-07',
        'fileCount': 2,
        'totalLines': 3,
        'files': [
          {'path': 'lib/main.dart', 'lines': 2, 'size': 10, 'content': 'void main() {}\n'},
          {'path': 'pubspec.yaml', 'lines': 1, 'size': 5, 'content': 'name: x'},
        ],
      }));
      expect(bundle.version, '4.7.0');
      expect(bundle.files.length, 2);
      expect(bundle.files.first.content, contains('void main'));
      expect(bundle.totalLines, 3);
    });
  });

  group('设置与形象默认值', () {
    test('智能体设置完整往返，步数被夹在合理区间', () {
      final s = AppSettings()
        ..agentEnabled = true
        ..agentConfirmEach = false
        ..agentAllowWorkspace = false
        ..agentAllowExternal = true
        ..agentAllowSystem = true
        ..agentAllowNetwork = true
        ..agentRiskAck = true
        ..agentMaxSteps = 99;
      final back = AppSettings()
        ..load(jsonDecode(s.encode()) as Map<String, dynamic>);
      expect(back.agentEnabled, isTrue);
      expect(back.agentConfirmEach, isFalse);
      expect(back.agentAllowWorkspace, isFalse);
      expect(back.agentAllowExternal, isTrue);
      expect(back.agentAllowSystem, isTrue);
      expect(back.agentAllowNetwork, isTrue);
      expect(back.agentRiskAck, isTrue);
      expect(back.agentMaxSteps, 8);
    });

    test('旧配置升级后智能体默认关闭，不额外获得任何权限', () {
      final s = AppSettings()..load(<String, dynamic>{});
      expect(s.agentEnabled, isFalse);
      expect(s.agentConfirmEach, isTrue);
      expect(s.agentAllowWorkspace, isTrue, reason: '沙箱内文件默认放开');
      expect(s.agentAllowExternal, isFalse);
      expect(s.agentAllowSystem, isFalse);
      expect(s.agentAllowNetwork, isFalse);
      expect(s.agentMaxSteps, 4);
    });

    test('默认不预置任何形象，没设置就是空列表', () {
      final list = defaultPersonas();
      expect(list, isEmpty);
      // 内部占位只为让取值不空指针，不进列表、不带文案。
      expect(nonePersona().name, isEmpty);
      expect(nonePersona().builtin, isTrue);
      expect(nonePersona().glyph, isEmpty, reason: '空 glyph 才会显示 App 图标');
    });

    test('旧配置里的内置人设会被清掉，自建形象保留', () {
      final s = AppSettings()
        ..load(<String, dynamic>{
          'personas': [
            {
              'id': 'persona_default',
              'name': 'Aigent',
              'glyph': 'A',
              'builtin': true,
            },
            {'id': 'persona_yan', 'name': '砚', 'glyph': '砚', 'builtin': true},
            {'id': 'persona_muse', 'name': 'Muse', 'glyph': 'M', 'builtin': true},
            {
              'id': 'persona_atlas',
              'name': 'Atlas',
              'glyph': 'A',
              'builtin': true
            },
            {'id': 'persona_mine', 'name': '牛來', 'glyph': '牛'},
          ],
          'activePersonaId': 'persona_yan',
        });
      expect(s.personas.length, 1);
      expect(s.personas.single.name, '牛來');
      // 原来选中的是被删掉的「砚」，回落到唯一保留的自建形象。
      expect(s.activePersonaId, 'persona_mine');
    });

    test('关闭智能体时 System Prompt 不含任何工具信息', () {
      final st = AppState()..settings = AppSettings();
      st.settings.ensurePresets();
      st.conversations = [Conversation(id: 'c1', title: 'A')];
      st.activeId = 'c1';
      final p = Persona(id: 'p', name: '测试', tagline: '', roleHint: '');
      final off = st.buildSystemPrompt(query: '你好', persona: p);
      expect(off.contains('[本机能力]'), isFalse);
      expect(off.contains('agent.device.info'), isFalse);

      st.settings.agentEnabled = true;
      final on = st.buildSystemPrompt(query: '你好', persona: p);
      expect(on, contains('[本机能力]'));
      expect(on, contains('agent.device.info'));
      expect(on, contains('隔离工作区'));
      expect(on, contains('硬边界'));
      expect(on, contains('设备信息'));
    });
  });

  group('v4.8 端侧离线语音包', () {
    test('未安装时状态安全回落，不抛异常', () async {
      final st = await SpeechModel.status();
      expect(st.ready, isFalse);
      expect(st.sizeLabel, '未下载');
    });

    test('体积文案按 MB 展示，空模型不显示 0.0 MB', () {
      expect(const SpeechModelStatus(ready: true).sizeLabel, '未下载');
      expect(
        const SpeechModelStatus(ready: true, bytes: 90 * 1024 * 1024).sizeLabel,
        '90.0 MB',
      );
    });

    test('模型目录名与引擎 id 稳定，避免升级后找不到已下载的包', () {
      expect(SpeechModel.dirName, 'vosk-model-small-cn-0.22');
      expect(SpeechModel.engineId, 'vosk-cn');
      expect(SpeechModel.downloadUrl, endsWith('.zip'));
    });
  });
}
