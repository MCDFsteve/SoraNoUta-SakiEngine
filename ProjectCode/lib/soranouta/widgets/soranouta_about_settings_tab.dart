import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';

/// 追加到引擎设置界面的项目页签（制作人员名单）。
List<SettingsTabContribution> soranoutaSettingsTabs() {
  return <SettingsTabContribution>[
    SettingsTabContribution(
      title: () => LocalizationManager().t('settings.tabs.about'),
      builder: (context) => const SoranoutaAboutSettingsTab(),
    ),
  ];
}

/// 设置 → 关于：制作人员名单。
///
/// 署名是制作人员本人的名字，任何界面语言下都保持原样；只有职责标签会随
/// 界面语言切换。
class SoranoutaAboutSettingsTab extends StatelessWidget {
  const SoranoutaAboutSettingsTab({super.key});

  /// 制作人员署名，顺序与 [_rolesFor] 返回的职责标签一一对应。
  static const List<String> _names = <String>[
    'irigaS',
    'flos',
    '变质',
    '猫嗝嗝嗝嗝颖',
    '软糖 梦熙 苏域',
  ];

  static List<String> _rolesFor(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.zhHans:
        return const <String>[
          '脚本 / 程序 / 演出',
          '视频 / 宣传',
          '演出',
          '美术',
          '配音',
        ];
      case SupportedLanguage.zhHant:
        return const <String>[
          '腳本 / 程式 / 演出',
          '影片 / 宣傳',
          '演出',
          '美術',
          '配音',
        ];
      case SupportedLanguage.en:
        return const <String>[
          'Script / Programming / Direction',
          'Video / Promotion',
          'Direction',
          'Art',
          'Voice Cast',
        ];
      case SupportedLanguage.ja:
        return const <String>[
          '脚本 / プログラム / 演出',
          '映像 / プロモーション',
          '演出',
          'アート',
          'キャスト',
        ];
    }
  }

  static String _sectionTitleFor(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.zhHans:
        return '制作人员';
      case SupportedLanguage.zhHant:
        return '製作人員';
      case SupportedLanguage.en:
        return 'Credits';
      case SupportedLanguage.ja:
        return 'スタッフ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);
    final language = LocalizationManager().currentLanguage;
    final roles = _rolesFor(language);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32 * uiScale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _sectionTitleFor(language),
              style: config.reviewTitleTextStyle.copyWith(
                fontSize:
                    config.reviewTitleTextStyle.fontSize! * textScale * 0.8,
                color: config.themeColors.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 10 * uiScale),
            Container(
              width: 64 * uiScale,
              height: 2 * uiScale,
              color: config.themeColors.primary.withValues(alpha: 0.5),
            ),
            SizedBox(height: 24 * uiScale),
            for (var index = 0; index < _names.length; index++) ...[
              _buildCreditRow(
                config: config,
                uiScale: uiScale,
                textScale: textScale,
                role: index < roles.length ? roles[index] : '',
                names: _names[index],
              ),
              SizedBox(height: 12 * uiScale),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreditRow({
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
    required String role,
    required String names,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20 * uiScale,
        vertical: 14 * uiScale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withValues(alpha: 0.5),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 260 * uiScale,
            child: Text(
              role,
              style: config.dialogueTextStyle.copyWith(
                fontSize:
                    config.dialogueTextStyle.fontSize! * textScale * 0.65,
                color: config.themeColors.primary.withValues(alpha: 0.72),
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(width: 16 * uiScale),
          Expanded(
            child: Text(
              names,
              style: config.reviewTitleTextStyle.copyWith(
                fontSize:
                    config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                color: config.themeColors.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
