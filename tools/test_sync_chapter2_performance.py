import tempfile
import unittest
from pathlib import Path

from tools.sync_chapter2_performance import rebuild_nvlm_blocks


class RebuildNvlmBlocksTest(unittest.TestCase):
    def rebuild(self, source_text: str, target_lines: list[str]) -> list[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_path = Path(temporary_directory) / "chapter.rpy"
            source_path.write_text(source_text, encoding="utf-8")
            rebuilt, _ = rebuild_nvlm_blocks(
                source_path,
                target_lines,
                renpy_character_aliases={"xp", "x"},
                renpy_nvl_aliases={"xp"},
                saki_character_aliases={"xcp2"},
            )
        return rebuilt

    def test_character_kind_controls_mode_and_clear_only_splits_pages(self) -> None:
        rebuilt = self.rebuild(
            """
nvl clear
xp "第一句"
xp "第二句"
nvl clear
xp "第三句"
x "普通对话"
nvl clear
xp "第四句"
""",
            [
                "nvlm",
                '"第一句"',
                "scene sky",
                '"第二句"',
                '"第三句"',
                'xcp2 "普通对话"',
                '"新增的普通旁白"',
                '"第四句"',
                "endnvlm",
            ],
        )

        self.assertEqual(
            rebuilt,
            [
                "nvlm",
                '"第一句"',
                "scene sky",
                '"第二句"',
                "endnvlm",
                "nvlm",
                '"第三句"',
                "endnvlm",
                'xcp2 "普通对话"',
                '"新增的普通旁白"',
                "nvlm",
                '"第四句"',
                "endnvlm",
            ],
        )

    def test_control_flow_boundary_never_leaves_nvlm_open(self) -> None:
        rebuilt = self.rebuild(
            """
xp "分支前"
xp "分支后"
""",
            [
                '"分支前"',
                "if route == 1",
                "jump branch",
                "endif",
                '"分支后"',
            ],
        )

        self.assertEqual(
            rebuilt,
            [
                "nvlm",
                '"分支前"',
                "endnvlm",
                "if route == 1",
                "jump branch",
                "endif",
                "nvlm",
                '"分支后"',
                "endnvlm",
            ],
        )


if __name__ == "__main__":
    unittest.main()
