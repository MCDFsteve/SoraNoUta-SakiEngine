# SoraNoUta

这是独立的 Flutter 项目层仓库结构（可直接 `flutter run`）。

- 引擎依赖: `../../Engine`（`sakiengine` 包）
- 项目代码包: `./ProjectCode`（`soranouta_project`）
- 资源目录: `Assets/`、`GameScript/`
- 默认项目标识: `default_game.txt`

启动方式（在本目录）:

```bash
flutter pub get
flutter run -d macos --dart-define=SAKI_GAME_PATH="$(pwd)"
```

## Windows 演出构建

在 Windows 的 Git Bash 中运行：

```bash
./build.sh windows showcase
```

第二个参数默认为 `release`；`./build.sh windows` 继续使用原发布流程。`showcase` 目前仅支持 Windows，使用 Flutter Release 并启用 `SAKI_SHOW_MODE=true` 与 `SAKI_SHOWCASE_GAME_DIR=Game/<项目名>`，保留引擎编辑工具，不预编译 SKS。

产物在 `build/windows/<架构>/runner/Release/`。程序旁的 `Game/SoraNoUta/` 包含可编辑的 `Assets/`、`GameScript*`、`game_config.txt`、`default_game.txt` 和 `icon.png`（如存在）；分发时保留整个 Release 目录。脚本或素材修改后可用 **Shift+R** 重载，Dart 代码修改仍须重新构建。

演出构建会临时排除 Flutter 资源清单中的媒体、剧本和旧 `.sakipak`，保留字体与着色器声明，避免重复打包或依赖缺失的旧资源包；成功或失败后都会恢复原 `pubspec.yaml` 和引擎脚本编译入口。

## 多语言

在「设置 → 画面设置 → 界面语言」切换简体中文、繁体中文、英语、日语或韩语。
语言设置会保留；首次启动按系统语言选择。配音、演出与素材使用原版资源。

- `GameScript/labels/`：开场、第零章与第一章的 2,745 条剧情文本在原句内嵌五语片段；只维护一套演出脚本。
- `GameScript/configs/characters.sks`：角色显示名也在同一个引号内嵌五语片段。
- 第二章暂不翻译，未标记的原文仍显示简体中文。
- 菜单、设置、存读档、开场字幕与鉴赏目录支持上述五种语言。

遵循引擎[脚本创作指南](../../docs/script-guide.md#脚本内嵌多语言)：

```sks
x "/zhs 你好/ /zhc 你好/ /en Hello/ /jp こんにちは/ /ko 안녕/"
```

只扩展引号内的显示文本，保持原文件行数、分支、配音和演出命令不变，以维持存档和回退节点的位置。语言片段内的斜杠按文档写为全角 `／`，例如 `[size=1.2]文字[／size]`、`[pass]文字[／pass]`，引擎保留其字号和瞬显效果。

用 **Shift+L** 逐句编辑译文及共享角色名，用 **Shift+P** 切换单语言脚本视图或完整源码。修改后运行 `flutter test test/localization_test.dart test/localization_preview_test.dart`。

英语人名采用中文拼音；日语保留汉字并在首次介绍时标注中文读音；韩语按中文读音音译。制作人员署名保留原样。韩语使用已打包的 `ChillJinshuSongPro_Soft` 补足默认黑体缺少的字形，无需依赖操作系统字体。

韩语支持及切换语言时刷新历史/NVL 的修复位于共享 `../../Engine` 仓库。发布时需同步使用本次引擎修改，并由正常构建流程重新生成脚本包；不要只复制项目而保留旧引擎或旧脚本缓存。
