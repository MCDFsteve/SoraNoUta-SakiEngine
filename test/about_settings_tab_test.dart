import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:soranouta_project/soranouta/widgets/soranouta_about_settings_tab.dart';

/// 设置 → 关于：制作人员名单的内容校验。
void main() {
  testWidgets('credits list shows every role and contributor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SoranoutaAboutSettingsTab()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('制作人员'), findsOneWidget);

    // 职责标签（简体中文界面）。
    for (final role in const <String>[
      '脚本 / 程序 / 演出',
      '视频 / 宣传',
      '演出',
      '美术',
      '配音',
    ]) {
      expect(find.text(role), findsOneWidget, reason: '缺少职责: $role');
    }

    // 署名必须逐字保留。
    for (final name in const <String>[
      'irigaS',
      'flos',
      '变质',
      '猫嗝嗝嗝嗝颖',
      '软糖 梦熙 苏域',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '缺少署名: $name');
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('project contributes exactly one About tab', (tester) async {
    // 注意：这里不调用 LocalizationManager().init()，它在测试环境会去加载整份
    // 游戏数据而卡住；标题是否取自引擎 key 可以直接比对，key 本身在四种语言下
    // 的存在性由引擎侧的 settings_screen_extra_tabs_test 覆盖。
    final tabs = soranoutaSettingsTabs();
    expect(tabs, hasLength(1));
    expect(
      tabs.single.title(),
      LocalizationManager().t('settings.tabs.about'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: tabs.single.builder)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('制作人员'), findsOneWidget);
    expect(find.text('irigaS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
