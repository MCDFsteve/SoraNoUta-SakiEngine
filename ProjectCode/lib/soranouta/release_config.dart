/// 《空之歌》的分割放送配置。
///
/// 当前发行版只开放序章与第一章。第二章制作完成并准备发布时，只需要把
/// [latestReleasedChapter] 改为 2；章节入口、第二章新游戏入口和第二章鉴赏
/// 会一起开放，而第一章通关记录仍沿用玩家已有的全局数据。
class SoranoutaReleaseConfig {
  SoranoutaReleaseConfig._();

  static const int latestReleasedChapter = 1;

  static const bool chapter2Released = latestReleasedChapter >= 2;
  static const bool chapter3Released = latestReleasedChapter >= 3;
  static const bool showChapterSelector = chapter2Released;
}
