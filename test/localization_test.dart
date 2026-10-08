import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/localization/script_localization_editing.dart';
import 'package:sakiengine/src/localization/script_localization_workspace.dart';
import 'package:sakiengine/src/utils/rich_text_parser.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/engine_asset_loader.dart';

const localizedLabels = <String>[
  'start',
  'cp0_001',
  'cp1_001',
  'cp1_002',
  'cp1_003',
  'cp1_004',
  'cp1_005',
  'cp1_006',
  'cp1_007',
];
final _quoted = RegExp(r'"(?:\\.|[^"\\])*"');
final _richTag = RegExp(r'\[(?:/?(?:size|pass)|w)(?:=[^\]]+)?\]');

List<String> _tags(String text) => _richTag
    .allMatches(text.replaceAll('／', '/'))
    .map((match) => match[0]!)
    .toList();

/// Source positions and control fields must stay stable for saves, rollback,
/// voice cues and language changes in the middle of a scene.
Object _controlIdentity(SksNode node) {
  if (node is SayNode) {
    return [
      node.character,
      node.sourceFile,
      node.sourceLine,
      node.inlineApiToken,
      node.dialogueTag,
      node.tailCharacter,
      node.tailPose,
      node.tailExpression,
      node.tailAnimation,
      node.tailRepeatCount,
      node.pose,
      node.expression,
      node.position,
      node.animation,
      node.repeatCount,
      node.startExpression,
      node.switchDelay,
      node.endExpression,
    ];
  }
  if (node is ConditionalSayNode) {
    return [
      node.character,
      node.sourceFile,
      node.sourceLine,
      node.conditionVariable,
      node.conditionValue,
      node.inlineApiToken,
      node.dialogueTag,
      node.tailCharacter,
      node.tailPose,
      node.tailExpression,
      node.tailAnimation,
      node.tailRepeatCount,
      node.pose,
      node.expression,
      node.position,
      node.animation,
      node.repeatCount,
    ];
  }
  if (node is MenuNode) {
    return node.choices.map((choice) => choice.targetLabel).toList();
  }
  if (node is JumpNode) {
    return [node.targetLabel, node.conditionVariable, node.conditionValue];
  }
  if (node is LabelNode) return node.name;
  return node.runtimeType.toString();
}

/// Read Unicode cmap formats 4/12 from the real TTF/OTF files. A style fallback
/// alone does not prove that the shipped font actually contains its glyphs.
Set<int> _fontCodePoints(ByteData data) {
  final result = <int>{};
  var cmap = -1;
  for (var table = 0; table < data.getUint16(4); table++) {
    final entry = 12 + table * 16;
    if (data.getUint32(entry) == 0x636d6170) {
      cmap = data.getUint32(entry + 8);
      break;
    }
  }
  if (cmap < 0) throw const FormatException('Font has no cmap table');
  for (var table = 0; table < data.getUint16(cmap + 2); table++) {
    final record = cmap + 4 + table * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    if (platform != 0 &&
        !(platform == 3 && (encoding == 1 || encoding == 10))) {
      continue;
    }
    final start = cmap + data.getUint32(record + 4);
    switch (data.getUint16(start)) {
      case 4:
        final count = data.getUint16(start + 6) ~/ 2;
        for (var segment = 0; segment < count; segment++) {
          final end = data.getUint16(start + 14 + segment * 2);
          final first = data.getUint16(start + 16 + count * 2 + segment * 2);
          final delta = data.getInt16(start + 16 + count * 4 + segment * 2);
          final rangeAddress = start + 16 + count * 6 + segment * 2;
          final rangeOffset = data.getUint16(rangeAddress);
          for (var code = first; code <= end && code < 0xffff; code++) {
            var glyph = rangeOffset == 0
                ? (code + delta) & 0xffff
                : data.getUint16(
                    rangeAddress + rangeOffset + (code - first) * 2,
                  );
            if (rangeOffset != 0 && glyph != 0) {
              glyph = (glyph + delta) & 0xffff;
            }
            if (glyph != 0) result.add(code);
          }
        }
      case 12:
        for (var group = 0; group < data.getUint32(start + 12); group++) {
          final offset = start + 16 + group * 12;
          final first = data.getUint32(offset);
          final end = data.getUint32(offset + 4);
          final glyph = data.getUint32(offset + 8);
          for (var code = first; code <= end; code++) {
            if (glyph + code - first != 0) result.add(code);
          }
        }
    }
  }
  return result;
}

const _languageTags = <SupportedLanguage, String>{
  SupportedLanguage.zhHans: 'zhs',
  SupportedLanguage.zhHant: 'zhc',
  SupportedLanguage.en: 'en',
  SupportedLanguage.ja: 'jp',
  SupportedLanguage.ko: 'ko',
};

String _resolveSource(String source, SupportedLanguage language) =>
    ScriptTextLocalizer.localizeQuotedText(source, language: language);

Iterable<String> _payloads(String source) => scriptQuotedRanges(
  source,
).map((range) => source.substring(range.start, range.end));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final relative in [
    ...localizedLabels.map((label) => 'labels/$label.sks'),
    'configs/characters.sks',
  ]) {
    test(
      '$relative has complete five-language inline text and lossless editor views',
      () {
        final source = File('GameScript/$relative').readAsStringSync();
        for (final payload in _payloads(source)) {
          if (payload.isEmpty) continue; // Invisible item display names.
          final editable = EditableLocalizedText(payload);
          expect(editable.languages, _languageTags.values.toSet());
          final tags = RegExp(
            r'/(zhs|zhc|en|jp|ko)\s',
          ).allMatches(payload).map((match) => match[1]!).toList();
          expect(
            tags,
            hasLength(5),
            reason: 'Duplicate/missing inline segment',
          );
          expect(tags.toSet(), _languageTags.values.toSet());
          final original = editable.value('zhs');
          for (final (language, tag) in _languageTags.entries.map(
            (e) => (e.key, e.value),
          )) {
            final translated = editable.value(tag);
            expect(
              translated.trim(),
              isNotEmpty,
              reason: '$relative $tag: $payload',
            );
            expect(
              translated,
              isNot(contains('/')),
              reason: 'ASCII slash delimits inline text',
            );
            expect(
              ScriptTextLocalizer.resolve(payload, language: language),
              translated,
            );
            expect(
              _tags(translated),
              _tags(original),
              reason: '$relative/$tag: rich tag order',
            );
            expect(
              editable.setValue(tag, translated),
              payload,
              reason: 'No-op editor save must be byte-identical',
            );
            // Full-width closers must have exactly the same effects as the legacy
            // spelling; translated text and wait/size/instant flags all survive.
            final legacy = translated
                .replaceAll('[／size]', '[/size]')
                .replaceAll('[／pass]', '[/pass]');
            List<Object?> segments(String text) =>
                RichTextParser.parseTextSegments(text)
                    .map(
                      (part) => [
                        part.text,
                        part.sizeMultiplier,
                        part.waitSeconds,
                        part.isInstantDisplay,
                      ],
                    )
                    .toList();
            expect(segments(translated), segments(legacy));
            expect(
              RichTextParser.cleanText(translated),
              RichTextParser.cleanText(legacy),
            );
          }
        }
        for (final (language, tag) in _languageTags.entries.map(
          (e) => (e.key, e.value),
        )) {
          final projected = LocalizedScriptProjection(source, tag);
          expect(projected.text, _resolveSource(source, language));
          projected.edit(projected.text);
          expect(
            projected.source,
            source,
            reason: '$relative/$tag: no-op round trip',
          );
          // Editing one visible line then undoing restores every other language
          // and all staging, even when translations contain rich-text closers.
          final range = scriptQuotedRanges(projected.text).first;
          final originalProjection = projected.text;
          projected.edit(
            originalProjection.replaceRange(
              range.start,
              range.end,
              'Translation QA',
            ),
          );
          expect(
            EditableLocalizedText(_payloads(projected.source).first).value(tag),
            'Translation QA',
          );
          for (final other in _languageTags.values.where(
            (other) => other != tag,
          )) {
            expect(
              EditableLocalizedText(
                _payloads(projected.source).first,
              ).value(other),
              EditableLocalizedText(_payloads(source).first).value(other),
            );
          }
          projected.edit(originalProjection);
          expect(
            projected.source,
            source,
            reason: '$relative/$tag: edit/undo round trip',
          );
        }
      },
    );
  }

  for (final language in SupportedLanguage.values) {
    test(
      '${language.code}: resolved AST keeps every index, source location and branch',
      () {
        var totalText = 0;
        for (final label in localizedLabels) {
          final source = File(
            'GameScript/labels/$label.sks',
          ).readAsStringSync();
          final resolved = _resolveSource(source, language);
          expect(
            const LineSplitter().convert(resolved).length,
            const LineSplitter().convert(source).length,
          );
          expect(
            resolved.replaceAll(_quoted, '"<text>"'),
            source.replaceAll(_quoted, '"<text>"'),
          );
          final original = SksParser()
              .parse(source, sourceFile: label)
              .children;
          final translated = SksParser()
              .parse(resolved, sourceFile: label)
              .children;
          expect(
            translated,
            hasLength(original.length),
            reason: '$label/${language.code}',
          );
          for (var index = 0; index < original.length; index++) {
            expect(
              translated[index].runtimeType,
              original[index].runtimeType,
              reason: '$label index $index',
            );
            expect(
              _controlIdentity(translated[index]),
              _controlIdentity(original[index]),
              reason: '$label index $index',
            );
          }
          final parsedCount = translated.fold<int>(
            0,
            (count, node) =>
                count +
                switch (node) {
                  SayNode() || ConditionalSayNode() => 1,
                  MenuNode(:final choices) => choices.length,
                  _ => 0,
                },
          );
          expect(
            parsedCount,
            _payloads(source).length,
            reason: '$label silently discarded a text line',
          );
          totalText += parsedCount;
        }
        expect(totalText, greaterThan(2700));
      },
    );
  }

  test(
    'all translations ship in the shared source; chapter two remains untranslated',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        manifest.listAssets().where((path) => path.startsWith('GameScript_')),
        isEmpty,
      );
      for (final relative in [
        ...localizedLabels.map((label) => 'labels/$label.sks'),
        'configs/characters.sks',
      ]) {
        expect(manifest.listAssets(), contains('GameScript/$relative'));
        expect(
          await EngineAssetLoader.loadString('assets/GameScript/$relative'),
          File('GameScript/$relative').readAsStringSync(),
        );
      }
      final cp2 = Directory('GameScript/labels')
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('cp2_'));
      expect(cp2, isNotEmpty);
      for (final file in cp2) {
        for (final payload in _payloads(file.readAsStringSync())) {
          expect(EditableLocalizedText(payload).languages, {
            'zhs',
          }, reason: file.path);
        }
      }
    },
  );

  test(
    'the multilingual editor persists shared names in characters.sks only',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'soranouta-inline-editor-',
      );
      addTearDown(() => scratch.delete(recursive: true));
      for (final relative in [
        ...localizedLabels.map((label) => 'labels/$label.sks'),
        'configs/characters.sks',
      ]) {
        final copy = File('${scratch.path}/GameScript/$relative');
        await copy.parent.create(recursive: true);
        await File('GameScript/$relative').copy(copy.path);
      }
      final workspace = await ScriptLocalizationWorkspace.load(scratch.path);
      expect(workspace.languages, _languageTags.values.toSet());
      final sharedName = workspace.speakers['x']!;
      expect(
        workspace.dialogue.where((row) => row.speaker == 'x').length,
        greaterThan(100),
      );
      final oldNames = {
        for (final tag in _languageTags.values) tag: sharedName.text.value(tag),
      };
      sharedName.setValue('ko', '공유 이름 테스트');
      expect(
        workspace.files.where((file) => file.isDirty).map((file) => file.path),
        ['${scratch.path}/GameScript/configs/characters.sks'],
      );
      expect(await workspace.save(), 1);
      final reopened = await ScriptLocalizationWorkspace.load(scratch.path);
      expect(reopened.speakers['x']!.text.value('ko'), '공유 이름 테스트');
      for (final tag in _languageTags.values.where((tag) => tag != 'ko')) {
        expect(reopened.speakers['x']!.text.value(tag), oldNames[tag]);
      }
      for (final label in localizedLabels) {
        expect(
          await File(
            '${scratch.path}/GameScript/labels/$label.sks',
          ).readAsString(),
          await File('GameScript/labels/$label.sks').readAsString(),
        );
      }
    },
  );

  test(
    'all five UI dictionaries have complete keys and matching placeholders',
    () async {
      final raw = await EngineAssetLoader.loadString(
        'assets/i18n/strings.json',
      );
      final dictionaries = jsonDecode(raw) as Map<String, dynamic>;
      final original = Map<String, String>.from(dictionaries['zh-Hans'] as Map);
      expect(original.length, greaterThanOrEqualTo(201));
      final placeholder = RegExp(r'\{[a-zA-Z_][a-zA-Z0-9_]*\}');
      List<String> placeholders(String text) =>
          placeholder.allMatches(text).map((m) => m[0]!).toList()..sort();
      for (final language in SupportedLanguage.values) {
        final translations = Map<String, String>.from(
          dictionaries[language.code] as Map,
        );
        expect(
          translations.keys.toSet(),
          original.keys.toSet(),
          reason: language.code,
        );
        for (final key in original.keys) {
          expect(
            translations[key]!.trim(),
            isNotEmpty,
            reason: '${language.code}: $key',
          );
          expect(
            placeholders(translations[key]!),
            placeholders(original[key]!),
            reason: '${language.code}: $key',
          );
        }
      }
    },
  );

  test(
    'bundled fonts cover every resolved story, character and UI glyph',
    () async {
      final available = <int>{};
      for (final path in [
        'Assets/fonts/SourceHanSansCN-Bold.ttf',
        'Assets/fonts/ChillJinshuSongPro_Soft.otf',
      ]) {
        available.addAll(_fontCodePoints(await rootBundle.load(path)));
      }
      final dictionaries =
          jsonDecode(
                await EngineAssetLoader.loadString('assets/i18n/strings.json'),
              )
              as Map<String, dynamic>;
      for (final language in SupportedLanguage.values) {
        final required = <int>{};
        for (final relative in [
          ...localizedLabels.map((label) => 'labels/$label.sks'),
          'configs/characters.sks',
        ]) {
          for (final payload in _payloads(
            File('GameScript/$relative').readAsStringSync(),
          )) {
            required.addAll(
              ScriptTextLocalizer.resolve(payload, language: language).runes,
            );
          }
        }
        for (final value in (dictionaries[language.code] as Map).values) {
          required.addAll((value as String).runes);
        }
        final missing =
            required
                .where(
                  (code) =>
                      code > 0x20 &&
                      code != 0xfe0f &&
                      !available.contains(code),
                )
                .toList()
              ..sort();
        expect(
          missing.map(
            (code) =>
                '${String.fromCharCode(code)} U+${code.toRadixString(16)}',
          ),
          isEmpty,
          reason: '${language.code}: missing glyphs would depend on OS fonts',
        );
      }
    },
  );

  test(
    'Korean inline aliases preserve documented full-width rich-text closers',
    () {
      expect(supportedLanguageFromCode('ko'), SupportedLanguage.ko);
      expect(SupportedLanguage.ko.locale.languageCode, 'ko');
      for (final tag in ['ko', 'kr']) {
        expect(
          ScriptTextLocalizer.resolve(
            '原文/en English//$tag 한국어/',
            language: SupportedLanguage.ko,
          ),
          '한국어',
        );
      }
      final resolved = ScriptTextLocalizer.resolve(
        '/zhs 你好/ /ko [size=1.2]샤유[w=0.4][／size][pass]안녕[／pass]/',
        language: SupportedLanguage.ko,
      );
      expect(RichTextParser.cleanText(resolved), '샤유안녕');
      final segments = RichTextParser.parseTextSegments(resolved);
      expect(segments.any((part) => part.waitSeconds == 0.4), isTrue);
      expect(segments.first.sizeMultiplier, 1.2);
      expect(segments.last.isInstantDisplay, isTrue);
      expect(
        ScriptTextLocalizer.resolve('원문 그대로', language: SupportedLanguage.ko),
        '원문 그대로',
      );
    },
  );
}
