import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

import 'animated_roller_blind.dart';

class SoranoutaChapterSelector extends StatefulWidget {
  const SoranoutaChapterSelector({
    super.key,
    required this.selectedChapter,
    required this.chapter2Unlocked,
    required this.onChapterSelected,
    required this.scale,
    this.startAnimation = true,
  });

  final int selectedChapter;
  final bool chapter2Unlocked;
  final ValueChanged<int> onChapterSelected;
  final double scale;
  final bool startAnimation;

  @override
  State<SoranoutaChapterSelector> createState() =>
      _SoranoutaChapterSelectorState();
}

class _SoranoutaChapterSelectorState extends State<SoranoutaChapterSelector> {
  final UISoundManager _uiSoundManager = UISoundManager();
  bool _expanded = false;
  int? _hoveredRow;

  void _toggleExpanded() {
    _uiSoundManager.playButtonClick();
    setState(() => _expanded = !_expanded);
  }

  void _selectChapter(int chapter) {
    if (chapter == 2 && !widget.chapter2Unlocked) {
      return;
    }
    _uiSoundManager.playButtonClick();
    setState(() => _expanded = false);
    widget.onChapterSelected(chapter);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = SettingsManager().currentDarkMode;
    final foregroundColor = isDarkMode ? Colors.black : Colors.white;
    final shadowColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.9);

    return AnimatedRollerBlind(
      startAnimation: widget.startAnimation,
      index: 0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Stack(
          children: [
            IgnorePointer(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: _buildPanel(color: shadowColor, interactive: false),
              ),
            ),
            _buildPanel(color: foregroundColor, interactive: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({required Color color, required bool interactive}) {
    final scale = widget.scale;
    final panelWidth = 210 * scale;

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 3 * scale),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRow(
            chapter: widget.selectedChapter,
            color: color,
            interactive: interactive,
            isHeader: true,
          ),
          Container(height: 2 * scale, color: color),
          if (_expanded) ...[
            _buildRow(chapter: 1, color: color, interactive: interactive),
            Container(height: 1 * scale, color: color.withValues(alpha: 0.7)),
            _buildRow(
              chapter: 2,
              color: color,
              interactive: interactive,
              locked: !widget.chapter2Unlocked,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow({
    required int chapter,
    required Color color,
    required bool interactive,
    bool isHeader = false,
    bool locked = false,
  }) {
    final rowId = isHeader ? 0 : chapter;
    final hovered = interactive && _hoveredRow == rowId;
    final isDarkMode = SettingsManager().currentDarkMode;
    final hoverColor = isDarkMode ? Colors.white : Colors.black;
    final effectiveColor = hovered ? hoverColor : color;
    final scale = widget.scale;

    final content = SizedBox(
      height: (isHeader ? 58 : 50) * scale,
      child: Padding(
        padding: EdgeInsets.only(left: 16 * scale, right: 10 * scale),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _chapterLabel(chapter),
                style: TextStyle(
                  fontFamily: 'ChillJinshuSongPro_Soft',
                  fontSize: (isHeader ? 36 : 31) * scale,
                  color: effectiveColor.withValues(alpha: locked ? 0.42 : 1),
                  fontWeight: FontWeight.normal,
                  letterSpacing: 2,
                ),
              ),
            ),
            Icon(
              locked
                  ? Icons.lock_outline
                  : (isHeader
                        ? (_expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down)
                        : (chapter == widget.selectedChapter
                              ? Icons.check
                              : null)),
              size: (isHeader ? 28 : 23) * scale,
              color: effectiveColor.withValues(alpha: locked ? 0.42 : 1),
            ),
          ],
        ),
      ),
    );

    if (!interactive) {
      return content;
    }

    final enabled = !locked;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) {
        setState(() => _hoveredRow = rowId);
        if (enabled) {
          _uiSoundManager.playButtonHover();
        }
      },
      onExit: (_) {
        if (_hoveredRow == rowId) {
          setState(() => _hoveredRow = null);
        }
      },
      child: GestureDetector(
        key: interactive
            ? ValueKey(
                isHeader
                    ? 'chapter-selector-header'
                    : 'chapter-selector-option-$chapter',
              )
            : null,
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? (isHeader ? _toggleExpanded : () => _selectChapter(chapter))
            : null,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: locked
              ? '${_chapterLabel(chapter)}，${_lockedLabel()}'
              : _chapterLabel(chapter),
          child: content,
        ),
      ),
    );
  }

  String _chapterLabel(int chapter) {
    final language = LocalizationManager().currentLanguage;
    switch (language) {
      case SupportedLanguage.en:
        return 'Chapter $chapter';
      case SupportedLanguage.ja:
        return chapter == 1 ? '第一章' : '第二章';
      case SupportedLanguage.zhHant:
        return chapter == 1 ? '第一章' : '第二章';
      case SupportedLanguage.zhHans:
        return chapter == 1 ? '第一章' : '第二章';
    }
  }

  String _lockedLabel() {
    switch (LocalizationManager().currentLanguage) {
      case SupportedLanguage.en:
        return 'Complete Chapter 1 to unlock';
      case SupportedLanguage.ja:
        return '第一章クリア後に解放';
      case SupportedLanguage.zhHant:
        return '通關第一章後解鎖';
      case SupportedLanguage.zhHans:
        return '通关第一章后解锁';
    }
  }
}
