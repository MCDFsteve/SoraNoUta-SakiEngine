import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/script_merger.dart';
import 'package:soranouta_project/soranouta/chapter_progress.dart';
import 'package:soranouta_project/soranouta/widgets/soranouta_chapter_selector.dart';

void main() {
  test(
    'chapter entry stays at start until chapter two is released and unlocked',
    () {
      expect(
        SoranoutaChapterProgress.resolveInitialScriptName(
          chapter2Unlocked: false,
          selectedChapter: 2,
        ),
        'start',
      );
      expect(
        SoranoutaChapterProgress.resolveInitialScriptName(
          chapter2Unlocked: true,
          selectedChapter: 2,
        ),
        'start',
      );
      expect(
        SoranoutaChapterProgress.resolveInitialScriptName(
          chapter2Unlocked: true,
          selectedChapter: 2,
          chapter2Released: true,
        ),
        'cp2_001',
      );
    },
  );

  test('chapter quick saves use separate namespaces', () {
    expect(
      SoranoutaChapterProgress.quickSaveNamespaceForChapter(1),
      'chapter_1',
    );
    expect(
      SoranoutaChapterProgress.quickSaveNamespaceForChapter(2),
      'chapter_2',
    );
  });

  test('legacy save scripts are assigned to the correct chapter', () {
    expect(SoranoutaChapterProgress.chapterForScript('start'), 1);
    expect(SoranoutaChapterProgress.chapterForScript('cp1_007'), 1);
    expect(SoranoutaChapterProgress.chapterForScript('cp2_001'), 2);
    expect(
      SoranoutaChapterProgress.scriptBelongsToChapter('cp2_010', 1),
      isFalse,
    );
  });

  test('the merged runtime script contains the chapter two entry', () async {
    final merger = ScriptMerger();
    await merger.getMergedScript();

    expect(merger.getFileStartIndex('start'), isNotNull);
    expect(merger.getFileStartIndex('cp1_007'), isNotNull);
    expect(merger.getFileStartIndex('cp2_001'), isNotNull);
    expect(
      merger.getFileStartIndex('cp2_001')!,
      greaterThan(merger.getFileStartIndex('cp1_007')!),
    );
  });

  testWidgets('chapter two remains disabled before chapter one completion', (
    tester,
  ) async {
    int? selectedChapter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SoranoutaChapterSelector(
            selectedChapter: 1,
            chapter2Unlocked: false,
            onChapterSelected: (chapter) => selectedChapter = chapter,
            scale: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chapter-selector-header')));
    await tester.pumpAndSettle();

    expect(find.text('第二章'), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('chapter-selector-option-2')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(selectedChapter, isNull);
  });

  testWidgets('chapter two can be selected after chapter one completion', (
    tester,
  ) async {
    int? selectedChapter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SoranoutaChapterSelector(
            selectedChapter: 1,
            chapter2Unlocked: true,
            onChapterSelected: (chapter) => selectedChapter = chapter,
            scale: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chapter-selector-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chapter-selector-option-2')));
    await tester.pumpAndSettle();

    expect(selectedChapter, 2);
  });
}
