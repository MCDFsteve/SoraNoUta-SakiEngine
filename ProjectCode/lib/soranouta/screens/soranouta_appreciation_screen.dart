import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/rendering/composite_cg_renderer.dart';
import 'package:sakiengine/src/utils/character_composite_cache.dart';
import 'package:sakiengine/src/utils/expression_offset_manager.dart';
import 'package:sakiengine/src/utils/music_manager.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';
import 'package:sakiengine/src/widgets/movie_player.dart';

import 'appreciation_catalog.dart';

enum _AppreciationSection { characters, cg, backgrounds, music, movies }

/// 《空之歌》项目专用鉴赏界面。
///
/// 引擎提供资源解析、差分合成和音频播放，本界面负责本作实际资源的分组、
/// 命名和浏览体验。
class SoranoutaAppreciationScreen extends StatefulWidget {
  const SoranoutaAppreciationScreen({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SoranoutaAppreciationScreen> createState() =>
      _SoranoutaAppreciationScreenState();
}

class _SoranoutaAppreciationScreenState
    extends State<SoranoutaAppreciationScreen> {
  final UISoundManager _uiSoundManager = UISoundManager();

  _AppreciationSection _section = _AppreciationSection.characters;
  int _characterIndex = 0;
  String _characterPose = appreciationCharacters.first.poses.first;
  String _characterExpression = appreciationCharacters.first.defaultExpression;
  int? _activeCgIndex;
  int _activeCgVariant = 0;
  int? _activeBackgroundIndex;
  int? _activeMovieIndex;
  bool _viewerUiVisible = true;
  String? _playingMusicId;
  bool _musicBusy = false;
  bool _moviePlaying = false;
  bool _characterExportBusy = false;
  Duration _moviePosition = Duration.zero;
  int _moviePlaybackRevision = 0;
  Timer? _movieUiHideTimer;

  static const Duration _movieUiAutoHideDelay = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    final offsetManager = ExpressionOffsetManager();
    final offsets = offsetManager.getAllConfigs();
    if (!offsets.containsKey('xiayo1_pose6') ||
        !offsets.containsKey('xiayo1_pose7') ||
        !offsets.containsKey('xiayo1_pose8')) {
      // 鉴赏可以从主菜单直接进入；此时游戏流程尚未加载角色配置。
      // 复用正文的默认偏移，确保夏悠高身姿势的脸部差分正确对齐。
      offsetManager.initializeDefaultConfigs();
    }
    final currentMusic = MusicManager().currentBackgroundMusic;
    if (currentMusic != null) {
      for (final track in appreciationMusic) {
        if (currentMusic.endsWith('/${track.id}.mp3')) {
          _playingMusicId = track.id;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _movieUiHideTimer?.cancel();
    super.dispose();
  }

  void _cancelMovieUiAutoHide() {
    _movieUiHideTimer?.cancel();
    _movieUiHideTimer = null;
  }

  void _scheduleMovieUiAutoHide() {
    _cancelMovieUiAutoHide();
    if (!_moviePlaying || _activeMovieIndex == null) {
      return;
    }
    _movieUiHideTimer = Timer(_movieUiAutoHideDelay, () {
      _movieUiHideTimer = null;
      if (!mounted ||
          !_moviePlaying ||
          _activeMovieIndex == null ||
          !_viewerUiVisible) {
        return;
      }
      setState(() => _viewerUiVisible = false);
    });
  }

  void _toggleMovieUi() {
    final showUi = !_viewerUiVisible;
    setState(() => _viewerUiVisible = showUi);
    if (showUi) {
      _scheduleMovieUiAutoHide();
    } else {
      _cancelMovieUiAutoHide();
    }
  }

  void _revealMovieUi() {
    if (_activeMovieIndex == null) {
      return;
    }
    if (!_viewerUiVisible) {
      setState(() => _viewerUiVisible = true);
    }
    _scheduleMovieUiAutoHide();
  }

  void _selectSection(_AppreciationSection section) {
    if (_section == section) {
      return;
    }
    _uiSoundManager.playButtonClick();
    setState(() {
      _section = section;
      _activeCgIndex = null;
      _activeBackgroundIndex = null;
      _activeMovieIndex = null;
    });
  }

  void _selectCharacter(int index) {
    final character = appreciationCharacters[index];
    _uiSoundManager.playButtonClick();
    setState(() {
      _characterIndex = index;
      _characterPose = character.poses.first;
      _characterExpression = character.defaultExpression;
    });
  }

  bool get _supportsCharacterExport {
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

  Future<void> _exportCurrentCharacter(
    AppreciationCharacter character,
    _GalleryCopy copy,
  ) async {
    if (_characterExportBusy || !_supportsCharacterExport) {
      return;
    }

    _uiSoundManager.playButtonClick();
    final resourceId = character.id;
    final pose = _characterPose;
    final expression = _characterExpression;
    final fileName = '$resourceId-$pose-$expression.png';
    setState(() => _characterExportBusy = true);
    try {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'PNG', extensions: <String>['png']),
        ],
      );
      if (location == null || !mounted) {
        return;
      }

      final image = await CharacterCompositeCache.instance.preload(
        resourceId,
        pose,
        expression,
      );
      if (image == null) {
        throw StateError('Character composite could not be rendered.');
      }

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Character composite could not be encoded as PNG.');
      }
      final pngBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final outputPath = location.path.toLowerCase().endsWith('.png')
          ? location.path
          : '${location.path}.png';
      await XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: fileName,
      ).saveTo(outputPath);
      if (mounted) {
        _showCharacterExportMessage(copy.savePngSuccess);
      }
    } catch (error) {
      debugPrint('Failed to export character PNG: $error');
      if (mounted) {
        _showCharacterExportMessage(copy.savePngFailed, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _characterExportBusy = false);
      }
    }
  }

  void _showCharacterExportMessage(String message, {bool isError = false}) {
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

  Future<void> _toggleMusic(AppreciationMusic track) async {
    if (_musicBusy) {
      return;
    }
    setState(() => _musicBusy = true);
    _uiSoundManager.playButtonClick();
    try {
      final manager = MusicManager();
      if (_playingMusicId == track.id &&
          manager.currentBackgroundMusic == track.assetPath) {
        await manager.stopBackgroundMusic(
          fadeDuration: const Duration(milliseconds: 450),
        );
        if (mounted) {
          setState(() => _playingMusicId = null);
        }
      } else {
        await manager.playBackgroundMusic(
          track.assetPath,
          fadeDuration: const Duration(milliseconds: 700),
        );
        if (mounted) {
          setState(() => _playingMusicId = track.id);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _musicBusy = false);
      }
    }
  }

  Future<void> _openMovie(int index) async {
    _uiSoundManager.playButtonClick();
    try {
      await MusicManager().stopBackgroundMusic(
        fadeDuration: const Duration(milliseconds: 300),
      );
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _playingMusicId = null;
      _activeMovieIndex = index;
      _moviePlaying = true;
      _moviePosition = Duration.zero;
      _moviePlaybackRevision++;
      _viewerUiVisible = true;
    });
    _scheduleMovieUiAutoHide();
  }

  void _closeMovie() {
    _cancelMovieUiAutoHide();
    setState(() {
      _activeMovieIndex = null;
      _moviePlaying = false;
      _moviePosition = Duration.zero;
      _viewerUiVisible = true;
    });
  }

  void _restartMovie() {
    _uiSoundManager.playButtonClick();
    setState(() {
      _moviePosition = Duration.zero;
      _moviePlaying = true;
      _moviePlaybackRevision++;
      _viewerUiVisible = true;
    });
    _scheduleMovieUiAutoHide();
  }

  void _toggleMoviePlayback() {
    final activeIndex = _activeMovieIndex;
    if (activeIndex == null) {
      return;
    }
    final movie = appreciationMovies[activeIndex];
    if (_moviePosition >= movie.duration - const Duration(milliseconds: 300)) {
      _restartMovie();
      return;
    }
    _uiSoundManager.playButtonClick();
    final shouldPlay = !_moviePlaying;
    setState(() {
      _moviePlaying = shouldPlay;
      _viewerUiVisible = true;
    });
    if (shouldPlay) {
      _scheduleMovieUiAutoHide();
    } else {
      _cancelMovieUiAutoHide();
    }
  }

  void _updateMoviePosition(Duration position) {
    if (!mounted || _activeMovieIndex == null) {
      return;
    }
    if (position.inMilliseconds ~/ 250 ==
        _moviePosition.inMilliseconds ~/ 250) {
      return;
    }
    setState(() => _moviePosition = position);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    config.updateThemeForDarkMode();
    final copy = _GalleryCopy.forLanguage(
      LocalizationManager().currentLanguage,
    );
    final viewingArtwork =
        _activeCgIndex != null ||
        _activeBackgroundIndex != null ||
        _activeMovieIndex != null;

    return OverlayScaffold(
      title: copy.title,
      showHeader: !viewingArtwork,
      disableWindowTintOverlay: viewingArtwork,
      onClose: (_) => widget.onClose(),
      footer: viewingArtwork ? null : _buildFooter(copy, config),
      content: viewingArtwork
          ? Stack(
              children: [
                if (_activeCgIndex != null) _buildCgViewer(),
                if (_activeBackgroundIndex != null) _buildBackgroundViewer(),
                if (_activeMovieIndex != null) _buildMovieViewer(copy),
              ],
            )
          : Column(
              children: [
                _buildTabBar(copy, config),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(_section),
                      child: _buildSection(copy),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabBar(_GalleryCopy copy, SakiEngineConfig config) {
    final scale = context.scaleFor(ComponentType.ui);
    final tabs = <Widget>[
      _SectionTab(
        icon: Icons.person_outline,
        label: copy.characters,
        selected: _section == _AppreciationSection.characters,
        onTap: () => _selectSection(_AppreciationSection.characters),
      ),
      _SectionTab(
        icon: Icons.photo_library_outlined,
        label: copy.cg,
        selected: _section == _AppreciationSection.cg,
        onTap: () => _selectSection(_AppreciationSection.cg),
      ),
      _SectionTab(
        icon: Icons.landscape_outlined,
        label: copy.backgrounds,
        selected: _section == _AppreciationSection.backgrounds,
        onTap: () => _selectSection(_AppreciationSection.backgrounds),
      ),
      _SectionTab(
        icon: Icons.music_note_outlined,
        label: copy.music,
        selected: _section == _AppreciationSection.music,
        onTap: () => _selectSection(_AppreciationSection.music),
      ),
      _SectionTab(
        icon: Icons.movie_outlined,
        label: copy.movies,
        selected: _section == _AppreciationSection.movies,
        onTap: () => _selectSection(_AppreciationSection.movies),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 8 * scale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: tabs),
      ),
    );
  }

  Widget _buildFooter(_GalleryCopy copy, SakiEngineConfig config) {
    final scale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);
    final text = switch (_section) {
      _AppreciationSection.characters =>
        '${appreciationCharacters.length} ${copy.characters}  •  '
            '${appreciationCharacters.fold<int>(0, (sum, item) => sum + item.expressions.length)} ${copy.variants}',
      _AppreciationSection.cg =>
        '${appreciationCgs.length} ${copy.cg}  •  '
            '${appreciationCgs.fold<int>(0, (sum, item) => sum + item.variants.length)} ${copy.variants}',
      _AppreciationSection.backgrounds =>
        '${appreciationBackgrounds.length} ${copy.backgrounds}',
      _AppreciationSection.music => '${appreciationMusic.length} ${copy.music}',
      _AppreciationSection.movies =>
        '${appreciationMovies.length} ${copy.movies}',
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 12 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.primary.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
            color: config.themeColors.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: config.reviewTitleTextStyle.copyWith(
            color: config.themeColors.primary.withValues(alpha: 0.7),
            fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.38,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_GalleryCopy copy) {
    switch (_section) {
      case _AppreciationSection.characters:
        return _buildCharacterGallery(copy);
      case _AppreciationSection.cg:
        return _buildCgGallery(copy);
      case _AppreciationSection.backgrounds:
        return _buildBackgroundGallery(copy);
      case _AppreciationSection.music:
        return _buildMusicGallery(copy);
      case _AppreciationSection.movies:
        return _buildMovieGallery(copy);
    }
  }

  Widget _buildCharacterGallery(_GalleryCopy copy) {
    final character = appreciationCharacters[_characterIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final selector = _buildCharacterSelector(horizontal: !wide);
        final preview = _buildCharacterPreview(character, copy);
        final controls = _buildCharacterControls(character, copy);

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 190, child: selector),
                const SizedBox(width: 18),
                Expanded(child: preview),
                const SizedBox(width: 18),
                SizedBox(width: 330, child: controls),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              SizedBox(height: 58, child: selector),
              const SizedBox(height: 10),
              Expanded(child: preview),
              const SizedBox(height: 10),
              SizedBox(
                height: constraints.maxHeight < 650 ? 170 : 220,
                child: controls,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCharacterSelector({required bool horizontal}) {
    final children = <Widget>[
      for (var index = 0; index < appreciationCharacters.length; index++)
        Padding(
          padding: EdgeInsets.only(
            right: horizontal ? 8 : 0,
            bottom: horizontal ? 0 : 8,
          ),
          child: _CharacterButton(
            name: appreciationCharacters[index].name,
            selected: _characterIndex == index,
            onTap: () => _selectCharacter(index),
          ),
        ),
    ];

    return _GlassPanel(
      padding: const EdgeInsets.all(8),
      child: horizontal
          ? ListView(scrollDirection: Axis.horizontal, children: children)
          : ListView(children: children),
    );
  }

  Widget _buildCharacterPreview(
    AppreciationCharacter character,
    _GalleryCopy copy,
  ) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 0.85,
                colors: <Color>[
                  Color(0x344ec0ca),
                  Color(0x10000000),
                  Color(0x42000000),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight * 0.92;
                  final width = height * 9 / 16;
                  return SizedBox(
                    width: width
                        .clamp(160, constraints.maxWidth * 0.88)
                        .toDouble(),
                    height: height,
                    child: CgSlotWidget(
                      key: const ValueKey('appreciation_character_slot'),
                      resourceId: character.id,
                      pose: _characterPose,
                      expression: _characterExpression,
                      cacheRevision: CharacterCompositeCache.instance.revision,
                      isFadingOut: false,
                      skipAnimation: false,
                      useGpuAcceleration:
                          CompositeCgRenderer.isGpuAccelerationEnabled,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(character.name, style: _artTitleStyle),
                const SizedBox(height: 3),
                Text(
                  '${appreciationPoseLabel(_characterPose)}  ·  '
                  '${appreciationExpressionLabel(_characterExpression)}',
                  style: _secondaryStyle,
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            bottom: 12,
            child: _buildCharacterExportButton(character, copy),
          ),
          Positioned(
            right: 14,
            bottom: 12,
            child: Text(copy.layeredHint, style: _eyebrowStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterExportButton(
    AppreciationCharacter character,
    _GalleryCopy copy,
  ) {
    if (!_supportsCharacterExport) {
      return const SizedBox.shrink();
    }

    final colors = SakiEngineConfig().themeColors;
    return Tooltip(
      message: _characterExportBusy ? copy.savingPng : copy.savePng,
      child: Material(
        color: colors.surface.withValues(alpha: 0.58),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _characterExportBusy
              ? null
              : () => unawaited(_exportCurrentCharacter(character, copy)),
          hoverColor: colors.primary.withValues(alpha: 0.12),
          highlightColor: colors.primary.withValues(alpha: 0.16),
          child: SizedBox.square(
            dimension: 30,
            child: Center(
              child: _characterExportBusy
                  ? SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.7,
                        color: colors.primary,
                      ),
                    )
                  : Icon(
                      Icons.download_rounded,
                      size: 17,
                      color: colors.primary,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCharacterControls(
    AppreciationCharacter character,
    _GalleryCopy copy,
  ) {
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: ListView(
        children: [
          Text(copy.pose, style: _sectionTitleStyle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pose in character.poses)
                _ChoicePill(
                  label: appreciationPoseLabel(pose),
                  selected: _characterPose == pose,
                  onTap: () {
                    _uiSoundManager.playButtonClick();
                    setState(() => _characterPose = pose);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(copy.expression, style: _sectionTitleStyle),
              const Spacer(),
              Text(
                '${character.expressions.length} ${copy.variants}',
                style: _secondaryStyle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final expression in character.expressions)
                _ChoicePill(
                  label: appreciationExpressionLabel(expression),
                  selected: _characterExpression == expression,
                  onTap: () {
                    _uiSoundManager.playButtonClick();
                    setState(() => _characterExpression = expression);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCgGallery(_GalleryCopy copy) {
    return _buildArtworkGrid(
      itemCount: appreciationCgs.length,
      itemBuilder: (context, index) {
        final cg = appreciationCgs[index];
        return _ArtworkCard(
          title: cg.title,
          subtitle: cg.isComposite
              ? '${cg.variants.length} ${copy.variants}'
              : (cg.animated ? copy.animation : copy.singleImage),
          onTap: () {
            _uiSoundManager.playButtonClick();
            setState(() {
              _activeCgIndex = index;
              _activeCgVariant = 0;
              _viewerUiVisible = true;
            });
          },
          child: _buildCgImage(cg, 0, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _buildCgImage(
    AppreciationCg cg,
    int variantIndex, {
    required BoxFit fit,
  }) {
    if (!cg.isComposite) {
      return SmartAssetImage(
        assetName: cg.standaloneAsset!,
        fit: fit,
        loop: cg.animated,
        errorWidget: const _MissingArtwork(),
      );
    }

    final variant = cg.variants[variantIndex];
    return _CompositePreview(
      key: ValueKey('${cg.resourceId}-$variant-$fit'),
      resourceId: cg.resourceId!,
      pose: 'pose1',
      expression: variant,
      fallbackAssets: <String>[cg.baseAsset, cg.variantAsset(variant)],
      fit: fit,
    );
  }

  Widget _buildCgViewer() {
    final cg = appreciationCgs[_activeCgIndex!];
    final variantCount = cg.variants.length;
    final artwork = cg.isComposite
        ? CgSlotWidget(
            key: const ValueKey('appreciation_cg_slot'),
            resourceId: cg.resourceId!,
            pose: 'pose1',
            expression: cg.variants[_activeCgVariant],
            cacheRevision: CharacterCompositeCache.instance.revision,
            isFadingOut: false,
            skipAnimation: false,
            useGpuAcceleration: CompositeCgRenderer.isGpuAccelerationEnabled,
          )
        : SmartAssetImage(
            assetName: cg.standaloneAsset!,
            fit: BoxFit.cover,
            loop: cg.animated,
            errorWidget: const _MissingArtwork(),
          );

    return _ArtworkViewer(
      title: cg.title,
      uiVisible: _viewerUiVisible,
      counter: variantCount > 1
          ? '${_activeCgVariant + 1} / $variantCount'
          : null,
      onToggleUi: () => setState(() => _viewerUiVisible = !_viewerUiVisible),
      onClose: () => setState(() {
        _activeCgIndex = null;
        _viewerUiVisible = true;
      }),
      onPrevious: variantCount > 1
          ? () => setState(() {
              _activeCgVariant =
                  (_activeCgVariant - 1 + variantCount) % variantCount;
            })
          : null,
      onNext: variantCount > 1
          ? () => setState(() {
              _activeCgVariant = (_activeCgVariant + 1) % variantCount;
            })
          : null,
      child: SizedBox.expand(child: artwork),
    );
  }

  Widget _buildBackgroundGallery(_GalleryCopy copy) {
    return _buildArtworkGrid(
      itemCount: appreciationBackgrounds.length,
      itemBuilder: (context, index) {
        final background = appreciationBackgrounds[index];
        return _ArtworkCard(
          title: background.title,
          subtitle: background.id,
          onTap: () {
            _uiSoundManager.playButtonClick();
            setState(() {
              _activeBackgroundIndex = index;
              _viewerUiVisible = true;
            });
          },
          child: SmartAssetImage(
            assetName: background.assetName,
            fit: BoxFit.cover,
            errorWidget: const _MissingArtwork(),
          ),
        );
      },
    );
  }

  Widget _buildBackgroundViewer() {
    final index = _activeBackgroundIndex!;
    final background = appreciationBackgrounds[index];
    return _ArtworkViewer(
      title: background.title,
      uiVisible: _viewerUiVisible,
      counter: '${index + 1} / ${appreciationBackgrounds.length}',
      onToggleUi: () => setState(() => _viewerUiVisible = !_viewerUiVisible),
      onClose: () => setState(() {
        _activeBackgroundIndex = null;
        _viewerUiVisible = true;
      }),
      onPrevious: () => setState(() {
        _activeBackgroundIndex =
            (index - 1 + appreciationBackgrounds.length) %
            appreciationBackgrounds.length;
      }),
      onNext: () => setState(() {
        _activeBackgroundIndex = (index + 1) % appreciationBackgrounds.length;
      }),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: SizedBox.expand(
          key: ValueKey(background.id),
          child: SmartAssetImage(
            assetName: background.assetName,
            fit: BoxFit.cover,
            errorWidget: const _MissingArtwork(),
          ),
        ),
      ),
    );
  }

  Widget _buildArtworkGrid({
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1500
            ? 5
            : width >= 1120
            ? 4
            : width >= 760
            ? 3
            : width >= 480
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(18),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 16 / 10.7,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }

  Widget _buildMusicGallery(_GalleryCopy copy) {
    final activeTrack = _playingMusicId == null
        ? null
        : appreciationMusic
              .where((track) => track.id == _playingMusicId)
              .firstOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final nowPlaying = _NowPlayingPanel(
          track: activeTrack,
          copy: copy,
          onToggle: activeTrack == null
              ? null
              : () => unawaited(_toggleMusic(activeTrack)),
        );
        final list = _GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ListView.separated(
            itemCount: appreciationMusic.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: SakiEngineConfig().themeColors.primary.withValues(
                alpha: 0.14,
              ),
            ),
            itemBuilder: (context, index) {
              final track = appreciationMusic[index];
              final playing = track.id == _playingMusicId;
              return _MusicRow(
                index: index + 1,
                track: track,
                playing: playing,
                disabled: _musicBusy,
                onTap: () => unawaited(_toggleMusic(track)),
              );
            },
          ),
        );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                SizedBox(width: 330, child: nowPlaying),
                const SizedBox(width: 18),
                Expanded(child: list),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SizedBox(height: 155, child: nowPlaying),
              const SizedBox(height: 10),
              Expanded(child: list),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMovieGallery(_GalleryCopy copy) {
    return _buildArtworkGrid(
      itemCount: appreciationMovies.length,
      itemBuilder: (context, index) {
        final movie = appreciationMovies[index];
        return _ArtworkCard(
          title: movie.title,
          subtitle:
              '${movie.id.toUpperCase()}  ·  '
              '${_formatDuration(movie.duration)}',
          onTap: () => unawaited(_openMovie(index)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartAssetImage(
                assetName: movie.thumbnailAsset,
                fit: BoxFit.cover,
                errorWidget: const ColoredBox(color: Color(0xff17243a)),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x28111a28), Color(0xa80b111c)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xaaffffff)),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMovieViewer(_GalleryCopy copy) {
    final index = _activeMovieIndex!;
    final movie = appreciationMovies[index];
    final durationMs = movie.duration.inMilliseconds;
    final progress = durationMs <= 0
        ? 0.0
        : (_moviePosition.inMilliseconds / durationMs)
              .clamp(0.0, 1.0)
              .toDouble();

    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MouseRegion(
              onEnter: (_) => _revealMovieUi(),
              onHover: (_) => _revealMovieUi(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleMovieUi,
                onDoubleTap: _toggleMoviePlayback,
                child: MoviePlayer(
                  key: ValueKey('${movie.id}-$_moviePlaybackRevision'),
                  movieFile: movie.movieFile,
                  autoPlay: _moviePlaying,
                  looping: false,
                  fit: BoxFit.contain,
                  onPositionChanged: _updateMoviePosition,
                  onVideoEnd: () {
                    if (!mounted || _activeMovieIndex != index) {
                      return;
                    }
                    _cancelMovieUiAutoHide();
                    setState(() {
                      _moviePosition = movie.duration;
                      _moviePlaying = false;
                      _viewerUiVisible = true;
                    });
                  },
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: IgnorePointer(
                  ignoring: !_viewerUiVisible,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _viewerUiVisible ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xc20a0f17),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x30ffffff)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: const Color(0x30ffffff),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              _BareViewerButton(
                                icon: Icons.close,
                                tooltip: copy.back,
                                onTap: _closeMovie,
                              ),
                              _BareViewerButton(
                                icon: Icons.replay_rounded,
                                tooltip: copy.replayMovie,
                                onTap: _restartMovie,
                              ),
                              _BareViewerButton(
                                icon: _moviePlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                tooltip: _moviePlaying
                                    ? copy.pauseMovie
                                    : copy.playMovie,
                                onTap: _toggleMoviePlayback,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  movie.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'SourceHanSansCN',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_formatDuration(_moviePosition)} / '
                                '${_formatDuration(movie.duration)}',
                                style: const TextStyle(
                                  color: Color(0xbfffffff),
                                  fontFamily: 'SourceHanSansCN',
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _artTitleStyle {
    final colors = SakiEngineConfig().themeColors;
    return TextStyle(
      color: colors.onSurface,
      fontFamily: 'SourceHanSansCN',
      fontSize: 22,
      fontWeight: FontWeight.bold,
    );
  }

  TextStyle get _sectionTitleStyle {
    final config = SakiEngineConfig();
    return config.reviewTitleTextStyle.copyWith(
      color: config.themeColors.primary,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
  }

  TextStyle get _secondaryStyle {
    return TextStyle(
      color: SakiEngineConfig().themeColors.onSurfaceVariant,
      fontFamily: 'SourceHanSansCN',
      fontSize: 12,
    );
  }

  TextStyle get _eyebrowStyle {
    return TextStyle(
      color: SakiEngineConfig().themeColors.primary.withValues(alpha: 0.7),
      fontFamily: 'SourceHanSansCN',
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 2.4,
    );
  }
}

class _GalleryCopy {
  const _GalleryCopy({
    required this.title,
    required this.characters,
    required this.cg,
    required this.backgrounds,
    required this.music,
    required this.movies,
    required this.back,
    required this.pose,
    required this.expression,
    required this.variant,
    required this.variants,
    required this.layeredHint,
    required this.animation,
    required this.singleImage,
    required this.nowPlaying,
    required this.chooseMusic,
    required this.playMovie,
    required this.pauseMovie,
    required this.replayMovie,
    required this.savePng,
    required this.savingPng,
    required this.savePngSuccess,
    required this.savePngFailed,
  });

  factory _GalleryCopy.forLanguage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.zhHant:
        return const _GalleryCopy(
          title: '鑑賞',
          characters: '角色立繪',
          cg: 'CG',
          backgrounds: '背景',
          music: '音樂',
          movies: '影片',
          back: '返回',
          pose: '姿勢',
          expression: '表情差分',
          variant: '差分',
          variants: '個差分',
          layeredHint: '姿勢 × 表情',
          animation: '動畫',
          singleImage: '單張',
          nowPlaying: '正在播放',
          chooseMusic: '選一首音樂',
          playMovie: '播放',
          pauseMovie: '暫停',
          replayMovie: '重新播放',
          savePng: '儲存 PNG',
          savingPng: '儲存中…',
          savePngSuccess: '透明 PNG 已儲存',
          savePngFailed: 'PNG 儲存失敗',
        );
      case SupportedLanguage.en:
        return const _GalleryCopy(
          title: 'Gallery',
          characters: 'Characters',
          cg: 'CG',
          backgrounds: 'Backgrounds',
          music: 'Music',
          movies: 'Movies',
          back: 'Back',
          pose: 'Pose',
          expression: 'Expression',
          variant: 'Variant',
          variants: 'variants',
          layeredHint: 'POSE × EXPRESSION',
          animation: 'Animation',
          singleImage: 'Single image',
          nowPlaying: 'NOW PLAYING',
          chooseMusic: 'Choose a track',
          playMovie: 'Play',
          pauseMovie: 'Pause',
          replayMovie: 'Replay',
          savePng: 'Save PNG',
          savingPng: 'Saving…',
          savePngSuccess: 'Transparent PNG saved',
          savePngFailed: 'Could not save PNG',
        );
      case SupportedLanguage.ja:
        return const _GalleryCopy(
          title: '鑑賞',
          characters: '立ち絵',
          cg: 'CG',
          backgrounds: '背景',
          music: '音楽',
          movies: '映像',
          back: '戻る',
          pose: 'ポーズ',
          expression: '表情差分',
          variant: '差分',
          variants: '差分',
          layeredHint: 'ポーズ × 表情',
          animation: 'アニメーション',
          singleImage: '一枚絵',
          nowPlaying: '再生中',
          chooseMusic: '曲を選択',
          playMovie: '再生',
          pauseMovie: '一時停止',
          replayMovie: '最初から再生',
          savePng: 'PNGを保存',
          savingPng: '保存中…',
          savePngSuccess: '透過PNGを保存しました',
          savePngFailed: 'PNGを保存できませんでした',
        );
      case SupportedLanguage.zhHans:
        return const _GalleryCopy(
          title: '鉴赏',
          characters: '角色立绘',
          cg: 'CG',
          backgrounds: '背景',
          music: '音乐',
          movies: '影片',
          back: '返回',
          pose: '姿势',
          expression: '表情差分',
          variant: '差分',
          variants: '个差分',
          layeredHint: '姿势 × 表情',
          animation: '动画',
          singleImage: '单张',
          nowPlaying: '正在播放',
          chooseMusic: '选择一首音乐',
          playMovie: '播放',
          pauseMovie: '暂停',
          replayMovie: '重新播放',
          savePng: '保存 PNG',
          savingPng: '保存中…',
          savePngSuccess: '透明 PNG 已保存',
          savePngFailed: 'PNG 保存失败',
        );
    }
  }

  final String title;
  final String characters;
  final String cg;
  final String backgrounds;
  final String music;
  final String movies;
  final String back;
  final String pose;
  final String expression;
  final String variant;
  final String variants;
  final String layeredHint;
  final String animation;
  final String singleImage;
  final String nowPlaying;
  final String chooseMusic;
  final String playMovie;
  final String pauseMovie;
  final String replayMovie;
  final String savePng;
  final String savingPng;
  final String savePngSuccess;
  final String savePngFailed;
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: config.themeColors.surface.withValues(alpha: 0.42),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: config.themeColors.primaryDark.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? colors.primary : colors.onSurface,
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterButton extends StatelessWidget {
  const _CharacterButton({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 130, minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                name,
                style: TextStyle(
                  color: selected ? colors.primary : colors.onSurface,
                  fontFamily: 'SourceHanSansCN',
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.82)
          : colors.surface.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colors.onSurface,
              fontFamily: 'SourceHanSansCN',
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkCard extends StatefulWidget {
  const _ArtworkCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ArtworkCard> createState() => _ArtworkCardState();
}

class _ArtworkCardState extends State<_ArtworkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.018 : 1,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: colors.surface,
          shape: Border.all(
            color: _hovered
                ? colors.primary
                : colors.primary.withValues(alpha: 0.24),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Color(0x18000000),
                        Color(0xe8000000),
                      ],
                      stops: <double>[0.35, 0.58, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 11,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'SourceHanSansCN',
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xaaffffff),
                                fontFamily: 'SourceHanSansCN',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.open_in_full,
                        size: 17,
                        color: Color(0xc8ffffff),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkViewer extends StatefulWidget {
  const _ArtworkViewer({
    required this.title,
    required this.child,
    required this.onClose,
    required this.uiVisible,
    required this.onToggleUi,
    this.counter,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final String? counter;
  final Widget child;
  final VoidCallback onClose;
  final bool uiVisible;
  final VoidCallback onToggleUi;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<_ArtworkViewer> createState() => _ArtworkViewerState();
}

class _ArtworkViewerState extends State<_ArtworkViewer> {
  static const double _minZoom = 1;
  static const double _maxZoom = 3;
  static const double _zoomStep = 1.14;

  double _zoom = _minZoom;
  double _gestureStartZoom = _minZoom;
  Offset _pan = Offset.zero;
  Size _viewportSize = Size.zero;
  Duration _transformDuration = Duration.zero;

  @override
  void didUpdateWidget(covariant _ArtworkViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.uiVisible &&
        widget.uiVisible &&
        (_zoom != _minZoom || _pan != Offset.zero)) {
      _zoom = _minZoom;
      _pan = Offset.zero;
      _transformDuration = const Duration(milliseconds: 260);
    }
  }

  Offset _clampPan(Offset value, double zoom) {
    if (zoom <= _minZoom || _viewportSize.isEmpty) {
      return Offset.zero;
    }
    final maxDx = _viewportSize.width * (zoom - 1) / 2;
    final maxDy = _viewportSize.height * (zoom - 1) / 2;
    return Offset(
      value.dx.clamp(-maxDx, maxDx).toDouble(),
      value.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (widget.uiVisible || event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      final scrollEvent = resolvedEvent as PointerScrollEvent;
      if (scrollEvent.scrollDelta.dy == 0) {
        return;
      }
      final multiplier = scrollEvent.scrollDelta.dy < 0
          ? _zoomStep
          : 1 / _zoomStep;
      final nextZoom = (_zoom * multiplier).clamp(_minZoom, _maxZoom);
      if (nextZoom == _zoom || !mounted) {
        return;
      }
      setState(() {
        _zoom = nextZoom;
        _pan = _clampPan(_pan, nextZoom);
        _transformDuration = const Duration(milliseconds: 70);
      });
    });
  }

  void _handleSecondaryTap() {
    if (!widget.uiVisible && (_zoom != _minZoom || _pan != Offset.zero)) {
      setState(() {
        _zoom = _minZoom;
        _pan = Offset.zero;
        _transformDuration = const Duration(milliseconds: 260);
      });
    }
    widget.onToggleUi();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (widget.uiVisible) {
      return;
    }
    _gestureStartZoom = _zoom;
    _transformDuration = Duration.zero;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (widget.uiVisible) {
      return;
    }
    final nextZoom = details.pointerCount >= 2
        ? (_gestureStartZoom * details.scale).clamp(_minZoom, _maxZoom)
        : _zoom;
    final nextPan = nextZoom > _minZoom
        ? _clampPan(_pan + details.focalPointDelta, nextZoom)
        : Offset.zero;
    if (nextZoom == _zoom && nextPan == _pan) {
      return;
    }
    setState(() {
      _zoom = nextZoom;
      _pan = nextPan;
      _transformDuration = Duration.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = constraints.biggest;
            final transform = Matrix4.identity()
              ..setEntry(0, 0, _zoom)
              ..setEntry(1, 1, _zoom)
              ..setTranslationRaw(_pan.dx, _pan.dy, 0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTap: _handleSecondaryTap,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              trackpadScrollCausesScale: true,
              child: Material(
                color: const Color(0xff080b11),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    AnimatedContainer(
                      duration: _transformDuration,
                      curve: _zoom == _minZoom
                          ? Curves.easeOutCubic
                          : Curves.easeOut,
                      transform: transform,
                      transformAlignment: Alignment.center,
                      child: widget.child,
                    ),
                    Positioned(
                      left: 14,
                      bottom: MediaQuery.paddingOf(context).bottom + 12,
                      right: 14,
                      child: IgnorePointer(
                        ignoring: !widget.uiVisible,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          opacity: widget.uiVisible ? 1 : 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _BareViewerButton(
                                icon: Icons.close,
                                tooltip: 'Close',
                                onTap: widget.onClose,
                              ),
                              if (widget.onPrevious != null) ...[
                                const SizedBox(width: 2),
                                _BareViewerButton(
                                  icon: Icons.chevron_left,
                                  tooltip: 'Previous',
                                  onTap: widget.onPrevious!,
                                ),
                              ],
                              if (widget.onNext != null) ...[
                                const SizedBox(width: 2),
                                _BareViewerButton(
                                  icon: Icons.chevron_right,
                                  tooltip: 'Next',
                                  onTap: widget.onNext!,
                                ),
                              ],
                              const SizedBox(width: 10),
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: Text(
                                    [
                                      widget.title,
                                      ?widget.counter,
                                    ].join('  ·  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'SourceHanSansCN',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      shadows: [
                                        Shadow(
                                          color: Color(0xe0000000),
                                          blurRadius: 6,
                                        ),
                                        Shadow(
                                          color: Color(0xb0000000),
                                          blurRadius: 1,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BareViewerButton extends StatelessWidget {
  const _BareViewerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          containedInkWell: false,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.1),
          child: Icon(
            icon,
            size: 26,
            color: Colors.white,
            shadows: const [
              Shadow(color: Color(0xe0000000), blurRadius: 6),
              Shadow(
                color: Color(0xb0000000),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicRow extends StatelessWidget {
  const _MusicRow({
    required this.index,
    required this.track,
    required this.playing,
    required this.disabled,
    required this.onTap,
  });

  final int index;
  final AppreciationMusic track;
  final bool playing;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    return Material(
      color: playing
          ? colors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: playing ? colors.primary : colors.onSurfaceVariant,
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 11,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: playing
                      ? colors.primary
                      : colors.surface.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 21,
                  color: playing ? Colors.white : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: playing ? colors.primary : colors.onSurface,
                        fontFamily: 'SourceHanSansCN',
                        fontSize: 14,
                        fontWeight: playing
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      track.id,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontFamily: 'SourceHanSansCN',
                        fontSize: 9,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              if (playing) const _EqualizerBars(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingPanel extends StatelessWidget {
  const _NowPlayingPanel({
    required this.track,
    required this.copy,
    required this.onToggle,
  });

  final AppreciationMusic? track;
  final _GalleryCopy copy;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = SakiEngineConfig().themeColors;
    final backgroundAsset =
        track?.backgroundAsset ?? 'backgrounds/sky-yuu.webp';
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: SizedBox.expand(
              key: ValueKey(backgroundAsset),
              child: SmartAssetImage(
                assetName: backgroundAsset,
                fit: BoxFit.cover,
                errorWidget: const ColoredBox(color: Color(0xff17243a)),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x40111a28), Color(0xe80b111c)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  copy.nowPlaying,
                  style: TextStyle(
                    color: colors.primaryLight,
                    fontFamily: 'SourceHanSansCN',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  track?.title ?? copy.chooseMusic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'ChillJinshuSongPro_Soft',
                    fontSize: 28,
                    letterSpacing: 1.6,
                  ),
                ),
                if (track != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    track!.id,
                    style: const TextStyle(
                      color: Color(0x88ffffff),
                      fontFamily: 'SourceHanSansCN',
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: Material(
              color: colors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onToggle,
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Icon(
                    track == null
                        ? Icons.music_note_rounded
                        : Icons.stop_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars();

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return SizedBox(
          width: 29,
          height: 25,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bar(7 + 12 * value),
              _bar(18 - 10 * value),
              _bar(9 + 15 * (1 - value)),
              _bar(6 + 9 * value),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: SakiEngineConfig().themeColors.primary,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _CompositePreview extends StatefulWidget {
  const _CompositePreview({
    super.key,
    required this.resourceId,
    required this.pose,
    required this.expression,
    required this.fallbackAssets,
    required this.fit,
  });

  final String resourceId;
  final String pose;
  final String expression;
  final List<String> fallbackAssets;
  final BoxFit fit;

  @override
  State<_CompositePreview> createState() => _CompositePreviewState();
}

class _CompositePreviewState extends State<_CompositePreview> {
  late Future<ui.Image?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(_CompositePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceId != widget.resourceId ||
        oldWidget.pose != widget.pose ||
        oldWidget.expression != widget.expression) {
      _future = _resolve();
    }
  }

  Future<ui.Image?> _resolve() {
    return CharacterCompositeCache.instance.preload(
      widget.resourceId,
      widget.pose,
      widget.expression,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _future,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image != null) {
          return RawImage(
            image: image,
            fit: widget.fit,
            filterQuality: FilterQuality.high,
          );
        }
        return _buildFallback();
      },
    );
  }

  Widget _buildFallback() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final asset in widget.fallbackAssets)
          SmartAssetImage(
            assetName: asset,
            fit: widget.fit,
            errorWidget: const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class _MissingArtwork extends StatelessWidget {
  const _MissingArtwork();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xff151b25),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Color(0x60ffffff),
          size: 34,
        ),
      ),
    );
  }
}
