import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:soranouta_project/soranouta/soranouta_module.dart';

void main() {
  final module = SoranoutaModule();

  test('sunset scene aliases use dark-orange character lighting', () {
    for (final scene in <String>[
      'sky yuu',
      'home yuu2',
      'sky-yuu',
      'shiokegate17',
      'SKY-YUU',
    ]) {
      final lighting = module.resolveCharacterLighting(
        GameState(background: scene),
      );
      expect(lighting, isNotNull, reason: scene);
      expect(lighting!.multiplyColor, const Color(0xFFC56F3D), reason: scene);
      expect(lighting.strength, 0.42, reason: scene);
    }
  });

  test('night scene aliases use deep-blue character lighting', () {
    for (final scene in <String>[
      'sky yoru',
      'sky-yoru',
      'home-yoru',
      'sky-yuu-yoru-17',
    ]) {
      final lighting = module.resolveCharacterLighting(
        GameState(background: scene),
      );
      expect(lighting, isNotNull, reason: scene);
      expect(lighting!.multiplyColor, const Color(0xFF2F4778), reason: scene);
      expect(lighting.strength, 0.58, reason: scene);
    }
  });

  test('daytime and non-scene states keep the original sprite colors', () {
    for (final scene in <String?>[null, '', 'sky', 'otherroad-asa', 'bl']) {
      expect(
        module.resolveCharacterLighting(GameState(background: scene)),
        isNull,
        reason: '$scene',
      );
    }
  });
}
