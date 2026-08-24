import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soranouta_project/soranouta/screens/appreciation_sticker_catalog.dart';
import 'package:soranouta_project/soranouta/screens/soranouta_sticker_gallery.dart';

void main() {
  test('sticker catalog exposes stable unique assets and export names', () {
    expect(appreciationStickers, hasLength(190));
    expect(appreciationStickers.first.id, '001');
    expect(
      appreciationStickers.first.assetPath,
      'Assets/stickers/sticker_001.gif',
    );
    expect(appreciationStickers.last.id, '190');
    expect(
      appreciationStickers.last.assetPath,
      'Assets/stickers/sticker_190.gif',
    );
    expect(
      appreciationStickers.map((sticker) => sticker.assetPath).toSet(),
      hasLength(appreciationStickers.length),
    );
    expect(
      appreciationStickers.map((sticker) => sticker.exportFileName).toSet(),
      hasLength(appreciationStickers.length),
    );
    expect(
      appreciationStickers.every(
        (sticker) => sticker.exportFileName.endsWith('.gif'),
      ),
      isTrue,
    );
  });

  testWidgets('sticker gallery shows animated previews and export controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: SoranoutaStickerGallery(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('夏悠表情包'), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-save-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-card-001')), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-save-001')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sticker-card-001')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('sticker-preview-save-001')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
