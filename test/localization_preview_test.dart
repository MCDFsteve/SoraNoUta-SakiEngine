import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The engine depends on this interface. Replace its platform implementation so
// component previews never read or write the player's real save/settings files.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/unified_game_data_manager.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/choice_menu.dart';
import 'package:sakiengine/src/widgets/nvl_screen.dart';
import 'package:soranouta_project/soranouta/soranouta_module.dart';
import 'package:soranouta_project/soranouta/widgets/resonance_opening_canvas.dart';
import 'package:soranouta_project/soranouta/widgets/soranouta_dialogue_box.dart';
import 'package:soranouta_project/soranouta/widgets/soranouta_menu_buttons.dart';

// Regenerate native component PNGs in /tmp with:
// flutter test --dart-define=SAKI_LOCALIZATION_PREVIEWS=true test/localization_preview_test.dart
const _writePreviews = bool.fromEnvironment('SAKI_LOCALIZATION_PREVIEWS');
const _languages = [
  SupportedLanguage.en,
  SupportedLanguage.ja,
  SupportedLanguage.zhHant,
  SupportedLanguage.ko,
];
const _sizes = [Size(1280, 720), Size(960, 540)];

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String> getApplicationDocumentsPath() async => '$root/documents';
  @override
  Future<String> getTemporaryPath() async => '$root/cache';
  @override
  Future<String> getApplicationCachePath() async => '$root/cache';
}

class _OpeningPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      resonanceOpeningCanvas.paint(canvas, size, 0.7);
  @override
  bool shouldRepaint(_OpeningPainter oldDelegate) => false;
}

String _quotedTextAt(SupportedLanguage language, String label, int line) {
  final source = File(
    'GameScript/labels/$label.sks',
  ).readAsLinesSync()[line - 1];
  return ScriptTextLocalizer.resolve(
    RegExp(r'"(.*)"').firstMatch(source)![1]!,
    language: language,
  );
}

String _speaker(SupportedLanguage language) {
  final names = File('GameScript/configs/characters.sks').readAsLinesSync();
  return ScriptTextLocalizer.resolve(
    RegExp(
      r'"([^"]+)"',
    ).firstMatch(names.firstWhere((line) => line.startsWith('x :')))![1]!,
    language: language,
  );
}

Future<void> _writePng(WidgetTester tester, GlobalKey key, String name) async {
  if (!_writePreviews) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/soranouta-localization-$name.png').writeAsBytes(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final originalPaths = PathProviderPlatform.instance;
  late Directory scratch;

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('soranouta-font-preview-');
    PathProviderPlatform.instance = _IsolatedPaths(scratch.path);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => switch (call.method) {
        'isFullScreen' || 'isMaximized' => false,
        _ => null,
      },
    );
    // Load the actual bundled fonts; Flutter's test-only Ahem face is not a
    // valid test of Korean/kana/traditional Chinese glyph rendering.
    for (final (family, path) in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('SourceHanSansCN', 'Assets/fonts/SourceHanSansCN-Bold.ttf'),
      ('ChillJinshuSongPro_Soft', 'Assets/fonts/ChillJinshuSongPro_Soft.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
    await SakiEngineConfig().loadConfig();
    SoranoutaModule.configureTypography();
    await SettingsManager().init();
    await LocalizationManager().init();
    await UnifiedGameDataManager().setSoundEnabled(false, 'SoraNoUta');
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    // The settings poller is process-local; keep its harmless window mock until
    // the test isolate exits. All persistent data remains under this temp root.
    await scratch.delete(recursive: true);
  });

  test(
    'project typography carries the bundled CJK fallback in every text style',
    () {
      final config = SakiEngineConfig();
      expect(
        config.dialogueTextStyle.fontSize,
        30,
        reason: 'The preview must load the game config, not engine defaults.',
      );
      for (final style in [
        config.dialogueTextStyle,
        config.speakerTextStyle,
        config.choiceTextStyle,
        config.reviewTitleTextStyle,
        config.quickMenuTextStyle,
        SoranoutaModule().createTheme().textTheme.bodyMedium!,
      ]) {
        expect(style.fontFamilyFallback, contains('ChillJinshuSongPro_Soft'));
      }
    },
  );

  for (final language in _languages) {
    for (final size in _sizes) {
      final suffix =
          '${language.code}-${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('$suffix renders real ADV, NVL, choices, menu and opening', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.runAsync(
          () => LocalizationManager().switchLanguage(language),
        );
        if (size == _sizes.first) {
          // Switching languages keeps loading the same shared inline source;
          // text selection happens through ScriptTextLocalizer.
          await tester.runAsync(() async {
            for (final relative in [
              'labels/start.sks',
              'labels/cp0_001.sks',
              'configs/characters.sks',
            ]) {
              expect(
                await AssetManager().loadString('assets/GameScript/$relative'),
                File('GameScript/$relative').readAsStringSync(),
              );
            }
          });
        }
        final characters = ConfigParser().parseCharacters(
          File('GameScript/configs/characters.sks').readAsStringSync(),
        );
        final speaker = characters['x']!.name;
        expect(speaker, _speaker(language));
        final config = SakiEngineConfig();
        final parsed = SksParser().parse(
          ScriptTextLocalizer.localizeQuotedText(
            File('GameScript/labels/cp0_001.sks').readAsStringSync(),
            language: language,
          ),
        );
        final menu = parsed.children.whereType<MenuNode>().first;
        final longDialogue = _quotedTextAt(language, 'cp0_001', 392);
        final key = GlobalKey();

        Future<void> show(Widget content, String mode) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: SoranoutaModule().createTheme(),
              home: RepaintBoundary(
                key: key,
                child: Scaffold(
                  body: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'Assets/images/backgrounds/grass.webp',
                        fit: BoxFit.cover,
                      ),
                      content,
                    ],
                  ),
                ),
              ),
            ),
          );
          // ADV's arrow blinks continuously; pump a bounded duration instead
          // of pumpAndSettle, which would never finish.
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
          // Delayed menu entrance animations start after the first time jump.
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: '$suffix/$mode');
          await _writePng(tester, key, '$suffix-$mode');
        }

        await show(
          SoranoUtaDialogueBox(
            speaker: speaker,
            speakerAlias: 'x',
            dialogue: longDialogue,
            isFastForwarding: true,
            scriptIndex: 1,
          ),
          'adv',
        );
        expect(find.byType(SoranoUtaDialogueBox), findsOneWidget);
        expect(find.text(speaker), findsOneWidget);
        final renderedDialogue = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((text) => text.text.toPlainText())
            .join();
        expect(renderedDialogue, contains(longDialogue));
        // Long translations remain readable through the native scrolling area.
        final advScrollable = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .first;
        expect(advScrollable.position.viewportDimension, greaterThan(0));
        if (advScrollable.position.maxScrollExtent > 0) {
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -400),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(advScrollable.position.pixels, greaterThan(0));
          await _writePng(tester, key, '$suffix-adv-scrolled');
        }

        await show(
          NvlScreen(
            isFastForwarding: true,
            isMovieMode: true,
            nvlDialogues: [
              for (final line in [93, 94, 95, 96, 97, 98, 99])
                NvlDialogue(
                  dialogue: _quotedTextAt(language, 'cp0_001', line),
                  timestamp: DateTime(2026),
                ),
            ],
          ),
          'nvl',
        );
        expect(find.byType(NvlScreen), findsOneWidget);

        String? selected;
        await show(
          ChoiceMenu(
            menuNode: menu,
            isFastForwarding: true,
            onChoiceSelected: (label) => selected = label,
          ),
          'choices',
        );
        expect(find.text(menu.choices.first.text), findsOneWidget);
        await tester.tap(find.text(menu.choices.first.text));
        await tester.pump();
        expect(selected, menu.choices.first.targetLabel);

        await show(
          Builder(
            builder: (context) {
              final scale = context.scaleFor(ComponentType.ui);
              return SoranoutaMenuButtons.createButtonsWidget(
                onContinueGame: () {},
                onNewGame: () {},
                onLoadGame: () {},
                onAppreciation: () {},
                showAppreciation: true,
                onSettings: () {},
                onExit: () {},
                config: config,
                scale: scale,
                screenSize: size,
              );
            },
          ),
          'menu',
        );
        expect(
          find.text(LocalizationManager().t('menu.newGame')),
          findsOneWidget,
        );
        for (final fade in tester.widgetList<FadeTransition>(
          find.byType(FadeTransition),
        )) {
          expect(
            fade.opacity.value,
            1,
            reason: 'Menu preview must be visibly painted',
          );
        }

        await show(CustomPaint(painter: _OpeningPainter()), 'opening');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
