import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

import 'appreciation_sticker_catalog.dart';

/// Animated sticker section for the SoraNoUta appreciation gallery.
class SoranoutaStickerGallery extends StatefulWidget {
  const SoranoutaStickerGallery({super.key});

  @override
  State<SoranoutaStickerGallery> createState() =>
      _SoranoutaStickerGalleryState();
}

class _SoranoutaStickerGalleryState extends State<SoranoutaStickerGallery> {
  final UISoundManager _uiSoundManager = UISoundManager();

  int? _savingStickerIndex;
  bool _savingAll = false;
  int _saveAllProgress = 0;

  bool get _exportBusy => _savingStickerIndex != null || _savingAll;

  bool get _supportsExport {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  Future<Uint8List> _loadStickerBytes(AppreciationSticker sticker) async {
    final data = await rootBundle.load(sticker.assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _saveStickerTo(
    AppreciationSticker sticker,
    String outputPath,
  ) async {
    final bytes = await _loadStickerBytes(sticker);
    await XFile.fromData(
      bytes,
      mimeType: 'image/gif',
      name: sticker.exportFileName,
    ).saveTo(outputPath);
  }

  String _ensureGifExtension(String path) {
    return path.toLowerCase().endsWith('.gif') ? path : '$path.gif';
  }

  String _joinPath(String directory, String fileName) {
    if (directory.endsWith('/') || directory.endsWith(r'\')) {
      return '$directory$fileName';
    }
    return '$directory/$fileName';
  }

  Future<void> _exportSticker(int index, _StickerGalleryCopy copy) async {
    if (_exportBusy || !_supportsExport) {
      return;
    }

    final sticker = appreciationStickers[index];
    _uiSoundManager.playButtonClick();
    setState(() => _savingStickerIndex = index);
    try {
      final location = await getSaveLocation(
        suggestedName: sticker.exportFileName,
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'GIF', extensions: <String>['gif']),
        ],
      );
      if (location == null || !mounted) {
        return;
      }

      await _saveStickerTo(sticker, _ensureGifExtension(location.path));
      if (mounted) {
        _showExportMessage(copy.saveOneSuccess(sticker.title));
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to export sticker ${sticker.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showExportMessage(copy.saveOneFailed, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _savingStickerIndex = null);
      }
    }
  }

  Future<void> _exportAll(_StickerGalleryCopy copy) async {
    if (_exportBusy || !_supportsExport) {
      return;
    }

    _uiSoundManager.playButtonClick();
    setState(() {
      _savingAll = true;
      _saveAllProgress = 0;
    });
    try {
      final directory = await getDirectoryPath(
        confirmButtonText: copy.chooseFolder,
        canCreateDirectories: true,
      );
      if (directory == null || !mounted) {
        return;
      }

      var failures = 0;
      for (var index = 0; index < appreciationStickers.length; index++) {
        final sticker = appreciationStickers[index];
        try {
          await _saveStickerTo(
            sticker,
            _joinPath(directory, sticker.exportFileName),
          );
        } catch (error) {
          failures++;
          debugPrint('Failed to export sticker ${sticker.id}: $error');
        }
        if (mounted &&
            (index % 4 == 3 || index == appreciationStickers.length - 1)) {
          setState(() => _saveAllProgress = index + 1);
        }
      }

      if (mounted) {
        if (failures == 0) {
          _showExportMessage(copy.saveAllSuccess(appreciationStickers.length));
        } else {
          _showExportMessage(
            copy.saveAllPartial(
              appreciationStickers.length - failures,
              failures,
            ),
            isError: true,
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to export sticker pack: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showExportMessage(copy.saveAllFailed, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingAll = false;
          _saveAllProgress = 0;
        });
      }
    }
  }

  void _showExportMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? const Color(0xff9d3343) : null,
        ),
      );
  }

  void _openPreview(int index, _StickerGalleryCopy copy) {
    _uiSoundManager.playButtonClick();
    final sticker = appreciationStickers[index];
    unawaited(
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.86),
        builder: (dialogContext) => _StickerPreviewDialog(
          sticker: sticker,
          copy: copy,
          canSave: _supportsExport,
          onSave: () => unawaited(_exportSticker(index, copy)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _StickerGalleryCopy.forLanguage(
      LocalizationManager().currentLanguage,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            wide ? 22 : 12,
            wide ? 18 : 12,
            wide ? 22 : 12,
            8,
          ),
          child: Column(
            children: [
              _buildHeader(copy, wide: wide),
              const SizedBox(height: 14),
              Expanded(child: _buildStickerGrid(copy)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(_StickerGalleryCopy copy, {required bool wide}) {
    final colors = SakiEngineConfig().themeColors;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.heading,
          style: TextStyle(
            color: colors.primary,
            fontFamily: 'SourceHanSansCN',
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          copy.subtitle,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontFamily: 'SourceHanSansCN',
            fontSize: 11,
          ),
        ),
      ],
    );
    final saveAll = _supportsExport
        ? _SaveAllButton(
            label: _savingAll
                ? copy.savingAll(_saveAllProgress, appreciationStickers.length)
                : copy.saveAll,
            busy: _savingAll,
            disabled: _exportBusy,
            onTap: () => unawaited(_exportAll(copy)),
          )
        : Text(
            copy.desktopExportOnly,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontFamily: 'SourceHanSansCN',
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.42),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                saveAll,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: saveAll),
              ],
            ),
    );
  }

  Widget _buildStickerGrid(_StickerGalleryCopy copy) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1500
            ? 7
            : width >= 1180
            ? 6
            : width >= 900
            ? 5
            : width >= 660
            ? 4
            : width >= 420
            ? 3
            : 2;
        return GridView.builder(
          key: const ValueKey('appreciation-sticker-grid'),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.86,
          ),
          itemCount: appreciationStickers.length,
          itemBuilder: (context, index) {
            final sticker = appreciationStickers[index];
            return _StickerCard(
              key: ValueKey('sticker-card-${sticker.id}'),
              sticker: sticker,
              saveTooltip: copy.saveOne,
              showSave: _supportsExport,
              saving: _savingStickerIndex == index,
              disabled: _exportBusy,
              onOpen: () => _openPreview(index, copy),
              onSave: () => unawaited(_exportSticker(index, copy)),
            );
          },
        );
      },
    );
  }
}

class _StickerCard extends StatelessWidget {
  const _StickerCard({
    super.key,
    required this.sticker,
    required this.saveTooltip,
    required this.showSave,
    required this.saving,
    required this.disabled,
    required this.onOpen,
    required this.onSave,
  });

  final AppreciationSticker sticker;
  final String saveTooltip;
  final bool showSave;
  final bool saving;
  final bool disabled;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return Material(
      color: colors.surface.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: InkWell(
        onTap: onOpen,
        hoverColor: colors.primary.withValues(alpha: 0.08),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _StickerBackdrop(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 42),
              child: Image.asset(
                sticker.assetPath,
                fit: BoxFit.contain,
                cacheWidth: 384,
                cacheHeight: 384,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const _StickerLoadError(),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: Colors.black.withValues(alpha: 0.48),
                child: Text(
                  sticker.id,
                  style: const TextStyle(
                    color: Color(0xcfffffff),
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 9,
                  ),
                ),
              ),
            ),
            if (showSave)
              Positioned(
                right: 5,
                top: 5,
                child: Tooltip(
                  message: saveTooltip,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.52),
                    shape: const CircleBorder(),
                    child: InkResponse(
                      key: ValueKey('sticker-save-${sticker.id}'),
                      onTap: disabled ? null : onSave,
                      radius: 19,
                      child: SizedBox.square(
                        dimension: 35,
                        child: Center(
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.download_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xe8202936), Color(0xff111722)],
                  ),
                ),
                child: Text(
                  sticker.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerPreviewDialog extends StatelessWidget {
  const _StickerPreviewDialog({
    required this.sticker,
    required this.copy,
    required this.canSave,
    required this.onSave,
  });

  final AppreciationSticker sticker;
  final _StickerGalleryCopy copy;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: const Color(0xff101620),
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: (size.height * 0.86).clamp(360, 760),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sticker.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'SourceHanSansCN',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: copy.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _StickerBackdrop(),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Image.asset(
                      sticker.assetPath,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const _StickerLoadError(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'GIF  ·  ${sticker.id} / ${appreciationStickers.length}',
                    style: const TextStyle(
                      color: Color(0xaaffffff),
                      fontFamily: 'SourceHanSansCN',
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (canSave)
                    OutlinedButton.icon(
                      key: ValueKey('sticker-preview-save-${sticker.id}'),
                      onPressed: onSave,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(copy.saveOne),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerBackdrop extends StatelessWidget {
  const _StickerBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.9,
          colors: <Color>[
            Color(0x324ec0ca),
            Color(0xff18222d),
            Color(0xff101620),
          ],
        ),
      ),
    );
  }
}

class _StickerLoadError extends StatelessWidget {
  const _StickerLoadError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Color(0x70ffffff),
        size: 36,
      ),
    );
  }
}

class _SaveAllButton extends StatelessWidget {
  const _SaveAllButton({
    required this.label,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('sticker-save-all'),
      onPressed: disabled ? null : onTap,
      icon: busy
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          : const Icon(Icons.download_for_offline_outlined, size: 19),
      label: Text(label),
    );
  }
}

class _StickerGalleryCopy {
  const _StickerGalleryCopy({
    required this.heading,
    required this.subtitle,
    required this.saveOne,
    required this.saveAll,
    required this.chooseFolder,
    required this.desktopExportOnly,
    required this.close,
    required this.saveOneSuccessTemplate,
    required this.saveOneFailed,
    required this.savingAllTemplate,
    required this.saveAllSuccessTemplate,
    required this.saveAllPartialTemplate,
    required this.saveAllFailed,
  });

  factory _StickerGalleryCopy.forLanguage(SupportedLanguage language) {
    return switch (language) {
      SupportedLanguage.zhHant => const _StickerGalleryCopy(
        heading: '夏悠表情包',
        subtitle: 'CoffeeBean V1.7  ·  GIF 動態預覽',
        saveOne: '儲存 GIF',
        saveAll: '儲存全部',
        chooseFolder: '儲存全部',
        desktopExportOnly: 'GIF 儲存功能支援 Windows、macOS 與 Linux',
        close: '關閉',
        saveOneSuccessTemplate: '「{name}」已儲存',
        saveOneFailed: 'GIF 儲存失敗',
        savingAllTemplate: '儲存中 {done} / {total}',
        saveAllSuccessTemplate: '已儲存全部 {count} 個表情包',
        saveAllPartialTemplate: '已儲存 {saved} 個，{failed} 個失敗',
        saveAllFailed: '表情包儲存失敗',
      ),
      SupportedLanguage.en => const _StickerGalleryCopy(
        heading: 'Xiayou Sticker Pack',
        subtitle: 'CoffeeBean V1.7  ·  Animated GIF previews',
        saveOne: 'Save GIF',
        saveAll: 'Save all',
        chooseFolder: 'Save all',
        desktopExportOnly:
            'GIF export is available on Windows, macOS, and Linux',
        close: 'Close',
        saveOneSuccessTemplate: 'Saved “{name}”',
        saveOneFailed: 'Could not save GIF',
        savingAllTemplate: 'Saving {done} / {total}',
        saveAllSuccessTemplate: 'Saved all {count} stickers',
        saveAllPartialTemplate: 'Saved {saved}; {failed} failed',
        saveAllFailed: 'Could not save the sticker pack',
      ),
      SupportedLanguage.ja => const _StickerGalleryCopy(
        heading: '夏悠スタンプ',
        subtitle: 'CoffeeBean V1.7  ·  GIFアニメーションプレビュー',
        saveOne: 'GIFを保存',
        saveAll: 'すべて保存',
        chooseFolder: 'すべて保存',
        desktopExportOnly: 'GIF保存はWindows、macOS、Linuxで利用できます',
        close: '閉じる',
        saveOneSuccessTemplate: '「{name}」を保存しました',
        saveOneFailed: 'GIFを保存できませんでした',
        savingAllTemplate: '保存中 {done} / {total}',
        saveAllSuccessTemplate: '{count}個のスタンプを保存しました',
        saveAllPartialTemplate: '{saved}個保存、{failed}個失敗',
        saveAllFailed: 'スタンプを保存できませんでした',
      ),
      SupportedLanguage.zhHans => const _StickerGalleryCopy(
        heading: '夏悠表情包',
        subtitle: 'CoffeeBean V1.7  ·  GIF 动态预览',
        saveOne: '保存 GIF',
        saveAll: '保存全部',
        chooseFolder: '保存全部',
        desktopExportOnly: 'GIF 保存功能支持 Windows、macOS 与 Linux',
        close: '关闭',
        saveOneSuccessTemplate: '“{name}”已保存',
        saveOneFailed: 'GIF 保存失败',
        savingAllTemplate: '保存中 {done} / {total}',
        saveAllSuccessTemplate: '已保存全部 {count} 个表情包',
        saveAllPartialTemplate: '已保存 {saved} 个，{failed} 个失败',
        saveAllFailed: '表情包保存失败',
      ),
    };
  }

  final String heading;
  final String subtitle;
  final String saveOne;
  final String saveAll;
  final String chooseFolder;
  final String desktopExportOnly;
  final String close;
  final String saveOneSuccessTemplate;
  final String saveOneFailed;
  final String savingAllTemplate;
  final String saveAllSuccessTemplate;
  final String saveAllPartialTemplate;
  final String saveAllFailed;

  String saveOneSuccess(String name) {
    return saveOneSuccessTemplate.replaceAll('{name}', name);
  }

  String savingAll(int done, int total) {
    return savingAllTemplate
        .replaceAll('{done}', '$done')
        .replaceAll('{total}', '$total');
  }

  String saveAllSuccess(int count) {
    return saveAllSuccessTemplate.replaceAll('{count}', '$count');
  }

  String saveAllPartial(int saved, int failed) {
    return saveAllPartialTemplate
        .replaceAll('{saved}', '$saved')
        .replaceAll('{failed}', '$failed');
  }
}
