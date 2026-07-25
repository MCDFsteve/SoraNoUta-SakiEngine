import 'package:sakiengine/src/utils/global_variable_manager.dart';

/// 主菜单章节选择与通关解锁状态。
///
/// 使用 SakiEngine 的全局变量存储，状态独立于单个存档并会进入统一游戏数据。
class SoranoutaChapterProgress {
  SoranoutaChapterProgress._();

  static const String chapter1CompletedVariable =
      'soranouta.chapter1_completed';
  static const String selectedChapterVariable = 'soranouta.selected_chapter';
  static const String chapter1QuickSaveNamespace = 'chapter_1';
  static const String chapter2QuickSaveNamespace = 'chapter_2';

  static final GlobalVariableManager _variables = GlobalVariableManager();

  static Future<void> initialize() => _variables.init();

  static bool get isChapter2Unlocked => _variables.getBoolVariableSync(
    chapter1CompletedVariable,
    defaultValue: false,
  );

  static int get selectedChapter {
    final storedValue = _variables.getStringVariableSync(
      selectedChapterVariable,
      defaultValue: '1',
    );
    return isChapter2Unlocked && storedValue == '2' ? 2 : 1;
  }

  static String get initialScriptName => resolveInitialScriptName(
    chapter2Unlocked: isChapter2Unlocked,
    selectedChapter: selectedChapter,
  );

  static String resolveInitialScriptName({
    required bool chapter2Unlocked,
    required int selectedChapter,
  }) {
    return chapter2Unlocked && selectedChapter == 2 ? 'cp2_001' : 'start';
  }

  static String quickSaveNamespaceForChapter(int chapter) {
    return chapter == 2
        ? chapter2QuickSaveNamespace
        : chapter1QuickSaveNamespace;
  }

  static int chapterForScript(String currentScript) {
    return currentScript.trim().toLowerCase().startsWith('cp2_') ? 2 : 1;
  }

  static bool scriptBelongsToChapter(String currentScript, int chapter) {
    return chapterForScript(currentScript) == chapter;
  }

  static Future<void> completeChapter1() async {
    await initialize();
    await _variables.setBoolVariable(chapter1CompletedVariable, true);
  }

  static Future<bool> selectChapter(int chapter) async {
    await initialize();
    if (chapter != 1 && chapter != 2) {
      return false;
    }
    if (chapter == 2 && !isChapter2Unlocked) {
      return false;
    }
    await _variables.setStringVariable(
      selectedChapterVariable,
      chapter.toString(),
    );
    return true;
  }
}
