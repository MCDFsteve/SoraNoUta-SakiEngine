#!/usr/bin/env python3
"""Merge Chapter 2 Ren'Py performance cues into the authored SakiEngine text.

The SakiEngine Chapter 2 files intentionally keep their edited dialogue, routes,
and the replacement staging for cancelled CGs.  This tool aligns the Ren'Py and
SKS control/dialogue anchors, inserts the executable performance layer between
them, and rebuilds SakiEngine NVL blocks from Ren'Py character kinds.

Ren'Py attaches NVL behavior to ``Character(..., kind=nvl)``; ``nvl clear`` only
clears the accumulated page.  SakiEngine instead attaches NVL behavior to every
dialogue inside an ``nvlm``/``endnvlm`` block.  Treating ``nvl clear`` as a mode
switch therefore leaks ordinary ADV dialogue into NVL.  The reflow below uses
the source speaker's character kind for mode and uses ``nvl clear`` only as a
page boundary.

Generated blocks are delimited, so rerunning this script is deterministic.
"""

from __future__ import annotations

import argparse
import difflib
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RENPY_ROOT = Path(
    "/Library/Afolder/RenpyProject/SoraNoUta/game/code/story/chapter2"
)
DEFAULT_RENPY_CHARACTERS = (
    DEFAULT_RENPY_ROOT.parents[1] / "options" / "hito.rpy"
)
DEFAULT_SKS_ROOT = PROJECT_ROOT / "GameScript/labels"
DEFAULT_SAKI_CHARACTERS = PROJECT_ROOT / "GameScript/configs/characters.sks"

GENERATED_START = "// <renpy-performance"
GENERATED_END = "// </renpy-performance>"

PERFORMANCE_PREFIXES = (
    "scene ",
    "show ",
    "hide ",
    "cg ",
    "play ",
    "stop ",
    "pause",
    "shake",
)

BACKGROUND_MAP = {
    "sky": "sky",
    "sky 17": "sky-yuu",
    "sky 22": "sky-yoru",
    "bl": "bl",
    "ike": "ike",
    "hayasi": "hayasi",
    "home 9": "home-asa",
    "home 17": "home-yuu",
    "home 19": "home-yuu2",
    "stone 9": "stone-asa",
    "stone 17": "stone-yuu",
    "road 7": "road-asa",
    "other road 9": "otherroad-asa",
    "other road 17": "otherroad-yuu",
    "to school": "to-school",
    "store": "store",
    "class": "class",
    "classdoor": "classdoor",
    "ground": "ground",
    "schoolgate": "schoolgate",
    "schoolgate 17": "schoolgate-yuu",
    "hasi 17": "hasi-yuu",
    "shiokehome": "shiokehome",
    "shiokehome 17": "shiokehome-yuu",
    "shiokegate": "shiokegate",
    "shiokegate17": "shiokegate17",
    "oka 17": "oka-yuu",
    "lab": "lab",
    "hatake": "hatake",
}

ITEM_ALIASES = {
    "book": "bookitem",
    "money": "moneyitem",
    "paper": "paperitem",
    "paper2": "paper2item",
    "tea": "teaitem",
    "tonbo": "tonboitem",
}

# Ren'Py 的 `show <background>` 是覆盖层，`hide` 后会露出此前的 CG、
# 背景和人物；SakiEngine 的 `scene` 则会清场。以下位置必须明确重建
# 被遮住的舞台，不能把 hide 当成空操作。
OVERLAY_RESTORES = {
    ("cp2_001.rpy", 64): ["cg cg_cp2_pond 4"],
    ("cp2_005.rpy", 114): [
        "scene oka-yuu",
        "show xcp2 pose3 doyagao at cp2center",
    ],
    ("cp2_010.rpy", 79): [
        "scene schoolgate",
        "show xcp2 pose1 think at cp2center",
    ],
    ("cp2_012.rpy", 170): [
        "scene shiokehome",
        "show xcp2 pose1 tameiki2 at cp2center",
    ],
    ("cp2_016.rpy", 229): [
        "scene shiokegate",
        "show xcp2 pose1 happy2 at cp2right2",
    ],
}

# Ren'Py `scene` clears ordinary shown images, but does not clear a `screen`.
# SakiEngine's anime layer is independent of scenes, so ordinary-image smoke
# needs an explicit stop at the corresponding scene boundary.
ANIME_STOPS_BEFORE_SCENE = {
    ("cp2_013.rpy", 320),
}

POSITION_MAP = {
    "pose": "cp2center",
    "poose": "cp2center",
    "poseleft": "cp2left",
    "poseleft2": "cp2left2",
    "poseright": "cp2right",
    "poseright2": "cp2right2",
    "posebig": "cp2center",
    "posesmall": "cp2center",
    "posebigright": "cp2right",
    "posesmallright": "cp2right",
    "naka": "cp2item",
    "posetop": "cp2center",
    "posetopleft": "cp2left",
    "posetopright": "cp2right",
    "posedown": "cp2center",
    "posedownleft": "cp2left",
    "posedownleft2": "cp2left2",
    "posedownright": "cp2right",
    "posedownright2": "cp2right2",
    "rightin": "cp2right",
    "rightin2": "cp2right2",
    "leftin": "cp2left",
    "leftin2": "cp2left2",
    "posetoleft": "cp2left",
    "posetoleft2": "cp2left2",
    "poseleft2toleft": "cp2left",
    "poseright2topose": "cp2center",
    "posetoleftgonna": "cp2left",
    "posetoleftgonnagift": "cp2left",
    "posetoright": "cp2right",
    "posetoright2": "cp2right2",
    "poselefttoback": "cp2center",
    "poserighttoback": "cp2center",
    "poserighttoback2": "cp2center",
    "ajumpleft": "cp2left",
    "ajumpleft2": "cp2left2",
    "ajumpright": "cp2right",
    "ajumpright2": "cp2right2",
    "ajumprightx2": "cp2right",
    "left_shake_two_times": "cp2left",
    "left_xshake_two_times": "cp2left",
    "leftfuruu": "cp2left",
    "leftfuruu2": "cp2left2",
    "rightfuruu": "cp2right",
    "rightfuruu2": "cp2right2",
    "pekorialeft": "cp2left",
    "pekorileft": "cp2left",
    "pekorileft2": "cp2left2",
    "pekoriright": "cp2right",
    "pekoriright2": "cp2right2",
}

ANIMATION_MAP = {
    "ajump": ("cp2jump", None),
    "ajump2": ("cp2grow", None),
    "ajump3": ("cp2shrink", None),
    "ajump4": ("cp2spring_in", None),
    "ajumpx2": ("cp2jump2", None),
    "ajumpleft": ("cp2jump", None),
    "ajumpleft2": ("cp2jump", None),
    "ajumpright": ("cp2jump", None),
    "ajumpright2": ("cp2jump", None),
    "ajumprightx2": ("cp2jump2", None),
    "bigjump": ("cp2bigjump", None),
    "poose": ("cp2enlarge_bounce", None),
    "shake_loop": ("cp2hshake", 0),
    "shake_two_times": ("cp2hshake", None),
    "left_shake_two_times": ("cp2hshake", None),
    "xshake_two_times": ("cp2vshake", None),
    "left_xshake_two_times": ("cp2vshake", None),
    "furuu": ("cp2tremble", 4),
    "bigfuruu": ("cp2tremble", 4),
    "cg_furuu": ("cp2tremble", 4),
    "leftfuruu": ("cp2tremble", 4),
    "leftfuruu2": ("cp2tremble", 4),
    "rightfuruu": ("cp2tremble", 4),
    "rightfuruu2": ("cp2tremble", 4),
    "pekori": ("cp2nod", None),
    "pekorileft": ("cp2nod", None),
    "pekorileft2": ("cp2nod", None),
    "pekoriright": ("cp2nod", None),
    "pekoriright2": ("cp2nod", None),
    "pekorix2": ("cp2nod", 2),
    "rightin": ("cp2enter_right", None),
    "rightin2": ("cp2enter_right2", None),
    "leftin": ("cp2enter_left", None),
    "leftin2": ("cp2enter_left2", None),
    "posetoleft": ("cp2from_center_to_left", None),
    "posetoleft2": ("cp2from_center_to_left2", None),
    "poseleft2toleft": ("cp2from_center_to_left", None),
    "poseright2topose": ("cp2from_right2_to_center", None),
    "posetoleftgonna": ("cp2from_center_to_left", None),
    "posetoleftgonnagift": ("cp2from_center_to_left", None),
    "posetoright": ("cp2from_center_to_right", None),
    "posetoright2": ("cp2from_center_to_right2", None),
    "poselefttoback": ("cp2from_left_to_center", None),
    "poserighttoback": ("cp2from_right_to_center", None),
    "poserighttoback2": ("cp2from_right2_to_center", None),
    "posebig": ("cp2grow", None),
    "posesmall": ("cp2shrink", None),
    "posebigright": ("cp2grow", None),
    "posesmallright": ("cp2shrink", None),
    "posetop": ("cp2rise", None),
    "posetopleft": ("cp2rise", None),
    "posetopright": ("cp2rise", None),
    "posedown": ("cp2fall", None),
    "posedownleft": ("cp2fall", None),
    "posedownleft2": ("cp2fall", None),
    "posedownright": ("cp2fall", None),
    "posedownright2": ("cp2fall", None),
}

XIAYO_BASE_EXPRESSIONS = {
    "akireta",
    "akireta2",
    "akireta3",
    "akireta4",
    "ciallo",
    "ciallo2",
    "dame",
    "dame2",
    "dame3",
    "doyagao",
    "fusigi",
    "happy",
    "happy2",
    "hen",
    "kirakira",
    "kowa",
    "mesugaki",
    "mesugaki2",
    "mesugaki3",
    "mesugaki4",
    "moeru",
    "naku",
    "naku2",
    "neko",
    "ochikomu",
    "odoroki",
    "odoroki2",
    "rena",
    "rue",
    "shy",
    "shy1",
    "shy2",
    "shy3",
    "shy4",
    "shy5",
    "smile",
    "smile2",
    "smile3",
    "smilenaka",
    "smilenaka0",
    "smilenaka1",
    "smilenaka2",
    "smilenaka3",
    "smilenaka4",
    "tabetaibase",
    "tameiki",
    "tameiki2",
    "think",
    "think2",
    "think3",
    "unhappy",
    "wakuwaku",
    "wakuwaku2",
    "wakuwaku3",
    "what",
}
XIAYO_PLUGINS = {"kuraikaop", "nande", "nani", "shyp"}

SHIOKE_EXPRESSIONS = {
    "empty",
    "emm",
    "emm2",
    "eye",
    "eye2",
    "eye3",
    "eye4",
    "happy",
    "happy2",
    "kuraikao",
    "kuraikao2",
    "naku",
    "naku2",
    "unhappy",
}


@dataclass
class SourceCue:
    text: str
    line: int
    atl: list[str] = field(default_factory=list)


@dataclass
class SourceAnchor:
    key: str
    line: int
    cues_before: list[SourceCue]


@dataclass
class TargetAnchor:
    key: str
    line_index: int


@dataclass(frozen=True)
class SourceDialogue:
    key: str
    line: int
    is_nvl: bool
    nvl_page: int


@dataclass(frozen=True)
class TargetDialogue:
    key: str
    line_index: int


def normalize_text(text: str) -> str:
    text = text.replace("//s", "").replace("//n", "")
    text = re.sub(r"\{/?(?:cps|size)(?:=[^}]*)?\}", "", text)
    text = re.sub(r"\[/?size(?:=[^\]]*)?\]", "", text)
    text = text.replace("%%", "%")
    return re.sub(r"\s+", "", text)


def quoted_text(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or stripped.startswith(("#", "//")):
        return None
    if stripped.startswith(
        (
            "scene ",
            "show ",
            "play ",
            "image ",
            "menu ",
            "api ",
        )
    ):
        return None
    start = stripped.find('"')
    end = stripped.rfind('"')
    if start < 0 or end <= start:
        return None
    return stripped[start + 1 : end]


def control_anchor(line: str, *, renpy: bool) -> str | None:
    stripped = line.strip()
    label = re.match(r"label\s+([A-Za-z0-9_]+):?$", stripped)
    if label:
        return f"L:{label.group(1)}"
    jump = re.match(r"jump\s+([A-Za-z0-9_]+)$", stripped)
    if jump:
        return f"J:{jump.group(1)}"
    if stripped == "return":
        return "R:return"
    text = quoted_text(stripped)
    if text is not None:
        # Dialogue/menu text is a stronger cross-engine anchor than the alias.
        return f"D:{normalize_text(text)}"
    return None


def strip_generated(lines: list[str]) -> list[str]:
    result: list[str] = []
    inside = False
    for line in lines:
        if line.startswith(GENERATED_START):
            inside = True
            continue
        if inside and line.startswith(GENERATED_END):
            inside = False
            continue
        if not inside:
            result.append(line)
    if inside:
        raise ValueError("unterminated generated performance block")
    return result


def parse_source(path: Path) -> list[SourceAnchor]:
    lines = path.read_text(encoding="utf-8").splitlines()
    anchors: list[SourceAnchor] = []
    pending: list[SourceCue] = []
    index = 0
    while index < len(lines):
        raw = lines[index]
        stripped = raw.strip()
        line_number = index + 1

        anchor = control_anchor(stripped, renpy=True)
        if anchor is not None:
            anchors.append(SourceAnchor(anchor, line_number, pending))
            pending = []
            index += 1
            continue

        if is_source_performance(stripped):
            cue = SourceCue(stripped, line_number)
            if stripped.startswith("show ") and stripped.rstrip().endswith(":"):
                base_indent = len(raw) - len(raw.lstrip())
                lookahead = index + 1
                while lookahead < len(lines):
                    next_raw = lines[lookahead]
                    next_stripped = next_raw.strip()
                    next_indent = len(next_raw) - len(next_raw.lstrip())
                    if next_stripped and next_indent <= base_indent:
                        break
                    if next_stripped and not next_stripped.startswith("#"):
                        cue.atl.append(next_stripped)
                    lookahead += 1
                index = lookahead
            else:
                index += 1
            pending.append(cue)
            continue

        index += 1

    # A synthetic EOF anchor keeps cues that occur after the final dialogue.
    anchors.append(SourceAnchor("E:EOF", len(lines) + 1, pending))
    return anchors


def parse_target(lines: list[str]) -> list[TargetAnchor]:
    anchors: list[TargetAnchor] = []
    for index, line in enumerate(lines):
        anchor = control_anchor(line, renpy=False)
        if anchor is not None:
            anchors.append(TargetAnchor(anchor, index))
    anchors.append(TargetAnchor("E:EOF", len(lines)))
    return anchors


def parse_renpy_character_kinds(path: Path) -> tuple[set[str], set[str]]:
    """Return all Ren'Py Character aliases and the aliases declared kind=nvl."""

    aliases: set[str] = set()
    nvl_aliases: set[str] = set()
    definition = re.compile(
        r"^\s*define\s+([A-Za-z_]\w*)\s*=\s*Character\((.*)$"
    )
    for line in path.read_text(encoding="utf-8").splitlines():
        match = definition.match(line)
        if match is None:
            continue
        alias, arguments = match.groups()
        aliases.add(alias)
        if re.search(r"\bkind\s*=\s*nvl\b", arguments):
            nvl_aliases.add(alias)
    return aliases, nvl_aliases


def parse_saki_character_aliases(path: Path) -> set[str]:
    aliases: set[str] = set()
    definition = re.compile(r"^\s*([A-Za-z_]\w*)\s*:")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = definition.match(line)
        if match is not None:
            aliases.add(match.group(1))
    return aliases


def dialogue_parts(
    line: str,
    character_aliases: set[str],
    *,
    renpy: bool,
    inside_menu: bool = False,
) -> tuple[str, str] | None:
    """Extract normalized dialogue text and speaker from one source line."""

    stripped = line.strip()
    if not stripped or stripped.startswith(("#", "//", "$")):
        return None

    start = stripped.find('"')
    end = stripped.rfind('"')
    if start < 0 or end <= start:
        return None

    prefix = stripped[:start].strip()
    suffix = stripped[end + 1 :].strip()
    if prefix:
        speaker = prefix.split()[0]
        if speaker not in character_aliases:
            return None
    else:
        speaker = ""
        if renpy and suffix.startswith(":"):
            return None
        if not renpy and inside_menu:
            return None

    return normalize_text(stripped[start + 1 : end]), speaker


def parse_source_dialogues(
    path: Path,
    character_aliases: set[str],
    nvl_aliases: set[str],
) -> list[SourceDialogue]:
    dialogues: list[SourceDialogue] = []
    nvl_page = 0
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        if line.strip() == "nvl clear":
            nvl_page += 1
            continue
        parts = dialogue_parts(line, character_aliases, renpy=True)
        if parts is None:
            continue
        key, speaker = parts
        dialogues.append(
            SourceDialogue(
                key=key,
                line=line_number,
                is_nvl=speaker in nvl_aliases,
                nvl_page=nvl_page,
            )
        )
    return dialogues


def parse_target_dialogues(
    lines: list[str],
    character_aliases: set[str],
) -> list[TargetDialogue]:
    dialogues: list[TargetDialogue] = []
    menu_depth = 0
    for line_index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "menu":
            menu_depth += 1
            continue
        if stripped == "endmenu":
            menu_depth = max(0, menu_depth - 1)
            continue
        parts = dialogue_parts(
            line,
            character_aliases,
            renpy=False,
            inside_menu=menu_depth > 0,
        )
        if parts is not None:
            dialogues.append(TargetDialogue(parts[0], line_index))
    return dialogues


def align_dialogue_modes(
    source: list[SourceDialogue],
    target: list[TargetDialogue],
) -> tuple[list[tuple[bool, int]], int, int]:
    """Map each target dialogue to (is_nvl, page), defaulting additions to ADV."""

    matcher = difflib.SequenceMatcher(
        a=[dialogue.key for dialogue in source],
        b=[dialogue.key for dialogue in target],
        autojunk=False,
    )
    mapping: dict[int, SourceDialogue] = {}
    for source_start, target_start, size in matcher.get_matching_blocks():
        for offset in range(size):
            mapping[target_start + offset] = source[source_start + offset]

    positional_replacements = 0
    for tag, source_start, source_end, target_start, target_end in (
        matcher.get_opcodes()
    ):
        if tag != "replace":
            continue
        if source_end - source_start != target_end - target_start:
            continue
        for offset in range(source_end - source_start):
            mapping[target_start + offset] = source[source_start + offset]
            positional_replacements += 1

    modes: list[tuple[bool, int]] = []
    for target_index in range(len(target)):
        source_dialogue = mapping.get(target_index)
        if source_dialogue is None:
            # Target-authored additions are ordinary ADV unless explicitly
            # present as a kind=nvl source character in the Ren'Py script.
            modes.append((False, -1))
        else:
            modes.append(
                (source_dialogue.is_nvl, source_dialogue.nvl_page)
            )
    return modes, len(target) - len(mapping), positional_replacements


def has_control_boundary(lines: list[str], start: int, end: int) -> bool:
    boundary = re.compile(
        r"^(?:label|jump|return|menu|endmenu|if|elseif|else|endif)\b"
    )
    return any(boundary.match(lines[index].strip()) for index in range(start, end))


def validate_nvlm_layout(
    lines: list[str],
    character_aliases: set[str],
    expected_modes: list[tuple[bool, int]],
) -> None:
    depth = 0
    dialogue_index = 0
    menu_depth = 0
    for line in lines:
        stripped = line.strip()
        if stripped == "nvlm":
            depth += 1
            if depth != 1:
                raise ValueError("nested nvlm block after Chapter 2 reflow")
            continue
        if stripped == "endnvlm":
            depth -= 1
            if depth != 0:
                raise ValueError("orphan endnvlm after Chapter 2 reflow")
            continue
        if stripped == "menu":
            menu_depth += 1
            continue
        if stripped == "endmenu":
            menu_depth = max(0, menu_depth - 1)
            continue
        parts = dialogue_parts(
            line,
            character_aliases,
            renpy=False,
            inside_menu=menu_depth > 0,
        )
        if parts is None:
            continue
        if dialogue_index >= len(expected_modes):
            raise ValueError("dialogue count changed during Chapter 2 NVL reflow")
        expected_nvl = expected_modes[dialogue_index][0]
        if (depth == 1) != expected_nvl:
            raise ValueError(
                "dialogue mode mismatch after Chapter 2 NVL reflow: "
                f"{parts[0]}"
            )
        dialogue_index += 1

    if depth != 0:
        raise ValueError("unterminated nvlm block after Chapter 2 reflow")
    if dialogue_index != len(expected_modes):
        raise ValueError("dialogue count changed during Chapter 2 NVL reflow")


def rebuild_nvlm_blocks(
    source_path: Path,
    lines: list[str],
    renpy_character_aliases: set[str],
    renpy_nvl_aliases: set[str],
    saki_character_aliases: set[str],
) -> tuple[list[str], dict[str, int]]:
    """Rebuild movie-NVL blocks from source character kinds and clear pages."""

    without_old_blocks = [
        line
        for line in lines
        if line.strip() not in {"nvlm", "endnvlm"}
    ]
    source_dialogues = parse_source_dialogues(
        source_path,
        renpy_character_aliases,
        renpy_nvl_aliases,
    )
    target_dialogues = parse_target_dialogues(
        without_old_blocks,
        saki_character_aliases,
    )
    modes, unmatched, positional_replacements = align_dialogue_modes(
        source_dialogues,
        target_dialogues,
    )

    starts: set[int] = set()
    ends: set[int] = set()
    for index, target_dialogue in enumerate(target_dialogues):
        is_nvl, nvl_page = modes[index]
        if not is_nvl:
            continue

        previous_same_page = False
        if index > 0:
            previous_nvl, previous_page = modes[index - 1]
            previous_same_page = (
                previous_nvl
                and previous_page == nvl_page
                and not has_control_boundary(
                    without_old_blocks,
                    target_dialogues[index - 1].line_index + 1,
                    target_dialogue.line_index,
                )
            )
        if not previous_same_page:
            starts.add(target_dialogue.line_index)

        next_same_page = False
        if index + 1 < len(target_dialogues):
            next_nvl, next_page = modes[index + 1]
            next_same_page = (
                next_nvl
                and next_page == nvl_page
                and not has_control_boundary(
                    without_old_blocks,
                    target_dialogue.line_index + 1,
                    target_dialogues[index + 1].line_index,
                )
            )
        if not next_same_page:
            ends.add(target_dialogue.line_index)

    rebuilt: list[str] = []
    for line_index, line in enumerate(without_old_blocks):
        if line_index in starts:
            rebuilt.append("nvlm")
        rebuilt.append(line)
        if line_index in ends:
            rebuilt.append("endnvlm")

    validate_nvlm_layout(rebuilt, saki_character_aliases, modes)
    stats = {
        "source_dialogues": len(source_dialogues),
        "target_dialogues": len(target_dialogues),
        "nvl_dialogues": sum(1 for is_nvl, _ in modes if is_nvl),
        "adv_dialogues": sum(1 for is_nvl, _ in modes if not is_nvl),
        "nvl_runs": len(starts),
        "unmatched_dialogues": unmatched,
        "positional_replacements": positional_replacements,
    }
    return rebuilt, stats


def is_source_performance(stripped: str) -> bool:
    if not stripped or stripped.startswith("#"):
        return False
    return stripped.startswith(
        (
            "scene ",
            "show ",
            "hide ",
            "with ",
            "play ",
            "stop ",
            "pause ",
            "pause(",
        )
    )


def split_inline_with(text: str) -> tuple[str, str | None]:
    match = re.match(r"^(.*?)(?:\s+with\s+([^:\s]+(?:\([^)]*\))?))(:?)$", text)
    if not match:
        return text.rstrip(":"), None
    return (match.group(1).strip() + match.group(3), match.group(2))


def transition_name(source_name: str) -> str | None:
    lowered = source_name.lower()
    if lowered == "none":
        return None
    if "hpunch" in lowered or "vpunch" in lowered:
        return "punch"
    if "dissolve" in lowered:
        return "diss"
    if "fade" in lowered:
        return "fade"
    return "fade"


def append_transition(lines: list[str], source_transition: str) -> None:
    transition = transition_name(source_transition)
    if transition is None:
        return
    if transition == "punch":
        lines.append("shake duration 0.45 intensity 10 target background")
        return
    for index in range(len(lines) - 1, -1, -1):
        if lines[index].startswith(("scene ", "show ", "cg ")):
            if " with " not in lines[index]:
                lines[index] += f" with {transition}"
            return


def translate_audio(text: str) -> list[str]:
    play = re.match(r"play\s+(music|sound|audio|se)\s+([^\s#]+)(?:\s+(loop))?", text)
    if play:
        channel, name, loop = play.groups()
        target_channel = "music" if channel == "music" else "sound"
        suffix = " loop" if loop else ""
        return [f"play {target_channel} {name}{suffix}"]
    stop = re.match(r"stop\s+(music|sound|audio|se)", text)
    if stop:
        target_channel = "music" if stop.group(1) == "music" else "sound"
        return [f"stop {target_channel}"]
    return []


def translate_pause(text: str) -> list[str]:
    match = re.match(r"pause(?:\s+|\()([0-9.]+)\)?", text)
    return [f"pause {match.group(1)}"] if match else []


def parse_visual_name(text: str, command: str) -> tuple[str, str | None]:
    body, inline_transition = split_inline_with(text)
    value = body[len(command) :].strip().rstrip(":").strip()
    return value, inline_transition


def cg_command(name: str) -> str | None:
    parts = name.split()
    if parts[:2] == ["xiayocg", "7"] and len(parts) >= 3:
        return f"cg cg_cp2_pond {parts[2]}"
    if not parts:
        return None
    resource = parts[0]
    if resource in {"shincg1", "shincg2", "shincg8", "cg_shiokehomeinfire"}:
        return None
    if resource == "shincg9" and len(parts) == 1:
        return "cg shincg9_embrace 1"
    if resource == "shincg10" and len(parts) >= 2 and parts[1] in {"1", "5"}:
        return None
    if resource == "shincg6" and len(parts) == 1:
        return "cg shincg6 1"
    if resource == "shincg11" and len(parts) == 1:
        return "cg shincg11 1"
    if resource.startswith("shincg") or resource == "cgmoto":
        variant = parts[1] if len(parts) >= 2 else "1"
        return f"cg {resource} {variant}"
    return None


def position_and_animation(
    transform: str | None, atl: Iterable[str]
) -> tuple[str, str | None, int | None]:
    position = POSITION_MAP.get(transform or "", "cp2center")
    animation: str | None = None
    repeat: int | None = None
    if transform in ANIMATION_MAP:
        animation, repeat = ANIMATION_MAP[transform]

    atl_lines = list(atl)
    for line in atl_lines:
        match = re.match(r"xcenter\s+([0-9.]+)", line)
        if match:
            x = float(match.group(1))
            if x <= 0.22:
                position = "cp2left"
            elif x <= 0.35:
                position = "cp2left2"
            elif x >= 0.78:
                position = "cp2right"
            elif x >= 0.65:
                position = "cp2right2"
            elif x >= 0.55:
                position = "cp2midright"
            else:
                position = "cp2center"

    if any("xoffset" in line for line in atl_lines):
        animation, repeat = "cp2hshake", None
    elif sum("ycenter" in line for line in atl_lines) >= 4:
        animation, repeat = "cp2jump2", None
    elif any("ycenter" in line for line in atl_lines):
        animation = animation or "cp2tremble"
        if any(line == "repeat" for line in atl_lines):
            repeat = 4

    return position, animation, repeat


def build_show_tail(
    position: str,
    animation: str | None,
    repeat: int | None,
) -> str:
    tail = f" at {position}"
    if animation:
        tail += f" an {animation}"
    if repeat is not None:
        tail += f" repeat {repeat}"
    return tail


def translate_xiayo(tokens: list[str], transform: str | None, atl: list[str]) -> str:
    position, animation, repeat = position_and_animation(transform, atl)
    tail = build_show_tail(position, animation, repeat)

    joined = " ".join(tokens)
    if joined.startswith("think to pose3"):
        return f"show xcp2 pose2 doyagao{tail}"
    if "naku to think" in joined:
        return f"show xcp2 pose1 think{tail} with diss"
    if "pose3 eye" in joined:
        return f"show xcp2 pose1 tameiki2{tail} with diss"

    if tokens and tokens[0] == "pose4":
        expression = next(
            (token for token in tokens[1:] if token.startswith(("think", "happy", "smile", "nan"))),
            "think",
        )
        if expression == "think1":
            expression = "think"
        # Ren'Py pose4 is an abandoned Chapter 1 side-body draft. The attempted
        # Chapter 2 arm5+arm6 replacement has visible seams, so keep the
        # expression and use the stable neutral body instead.
        return f"show xcp2 pose1 {expression}{tail}"

    body2 = "body2" in tokens
    arm_match = next(
        (re.fullmatch(r"arm([1-7])", token) for token in tokens if token.startswith("arm")),
        None,
    )
    arm_number = int(arm_match.group(1)) if arm_match else 1
    if body2:
        pose_number = 12 if arm_number == 4 else 11
    else:
        # pose5 (arm5+arm6) is retired because its assembled arms do not align.
        # arm5's only story use is the frightened, hands-raised beat, for which
        # pose6 (arm7) preserves the intended silhouette.
        pose_number = 6 if arm_number >= 5 else arm_number

    base = next((token for token in tokens if token in XIAYO_BASE_EXPRESSIONS), "happy")
    plugins = [token for token in tokens if token in XIAYO_PLUGINS]
    if plugins:
        base = f"{base}-{plugins[0]}"
    return f"show xcp2 pose{pose_number} {base}{tail}"


def translate_shioke(tokens: list[str], transform: str | None, atl: list[str]) -> str:
    position, animation, repeat = position_and_animation(transform, atl)
    tail = build_show_tail(position, animation, repeat)
    if "unhappy" in tokens and "to" in tokens and "eye" in tokens:
        expression = "eye"
    else:
        expression = next((token for token in tokens if token in SHIOKE_EXPRESSIONS), "unhappy")
    body3 = "body3" in tokens
    arm_match = next(
        (re.fullmatch(r"arm([1-3])", token) for token in tokens if token.startswith("arm")),
        None,
    )
    arm_number = int(arm_match.group(1)) if arm_match else 1
    pose_number = 4 if body3 else arm_number
    return f"show xk pose{pose_number} {expression}{tail}"


def translate_future_character(
    alias: str,
    tokens: list[str],
    transform: str | None,
    atl: list[str],
) -> str:
    position, animation, repeat = position_and_animation(transform, atl)
    tail = build_show_tail(position, animation, repeat)
    pose = next((token for token in tokens if re.fullmatch(r"pose[1-3]", token)), "pose1")
    ignored = {"body1", "body2", "body3", "arm1", "arm2", "arm3", "to"}
    expression = next(
        (
            token
            for token in reversed(tokens)
            if token not in ignored and not token.startswith("pose")
        ),
        "neutral",
    )
    return f"show {alias} {pose} {expression}{tail}"


def translate_character_show(name: str, atl: list[str]) -> str | None:
    body = name.rstrip(":").strip()
    at_match = re.search(r"\s+at\s+([A-Za-z0-9_]+)", body)
    transform = at_match.group(1) if at_match else None
    if at_match:
        body = body[: at_match.start()].strip()
    body = re.sub(r"\s+with\s+\S+$", "", body)
    tokens = body.split()
    if not tokens:
        return None
    resource = tokens.pop(0)
    if resource == "xiayo":
        return translate_xiayo(tokens, transform, atl)
    if resource == "shioke":
        return translate_shioke(tokens, transform, atl)
    if resource == "chen":
        position, animation, repeat = position_and_animation(transform, atl)
        arm_match = next(
            (re.fullmatch(r"arm([1-4])", token) for token in tokens if token.startswith("arm")),
            None,
        )
        pose = f"pose{arm_match.group(1)}" if arm_match else "pose1"
        ignored = {"pose1", "body1", "arm1", "arm2", "arm3", "arm4"}
        expression = next((token for token in tokens if token not in ignored), "smile")
        return (
            f"show ccy {pose} {expression}"
            + build_show_tail(position, animation, repeat)
        )
    if resource == "gonna":
        return translate_future_character("lgcp2", tokens, transform, atl)
    if resource == "syozen":
        return translate_future_character("lscp2", tokens, transform, atl)
    if resource == "ijin":
        position, animation, repeat = position_and_animation(transform, atl)
        pose = next((token for token in tokens if token.startswith("pose")), "pose1")
        expression = next(
            (token for token in tokens if token not in {pose, "body1", "body2", "arm1"}),
            "normal",
        )
        return (
            f"show ijin {pose} {expression}"
            + build_show_tail(position, animation, repeat)
        )
    return None


def translate_scene(text: str) -> list[str]:
    name, inline_transition = parse_visual_name(text, "scene ")
    cg = cg_command(name)
    if cg:
        lines = [cg]
    elif name in {"shincg1", "shincg2", "shincg8", "cg_shiokehomeinfire"}:
        return []
    else:
        background = BACKGROUND_MAP.get(name)
        if background is None:
            return []
        lines = [f"scene {background}"]
    if inline_transition:
        append_transition(lines, inline_transition)
    return lines


def translate_show(cue: SourceCue) -> list[str]:
    name, inline_transition = parse_visual_name(cue.text, "show ")
    at_match = re.search(r"\s+at\s+([A-Za-z0-9_]+)$", name)
    show_transform = at_match.group(1) if at_match else None
    bare_name = name[: at_match.start()].strip() if at_match else name
    cg = cg_command(bare_name)
    if cg:
        lines = [cg]
    elif bare_name in BACKGROUND_MAP:
        lines = [f"scene {BACKGROUND_MAP[bare_name]}"]
        # cp2_001:210 is the authored day-to-evening sky shot. The Ren'Py
        # comment explicitly asks for a slight zoom and downward camera move.
        if bare_name == "sky 17" and cue.line == 210:
            lines[0] += " an cp2sky_pan"
    elif bare_name in ITEM_ALIASES:
        animation = "cp2item_in"
        if show_transform and show_transform != "naka":
            animation = ANIMATION_MAP.get(show_transform, (animation, None))[0]
        lines = [
            f"show {ITEM_ALIASES[bare_name]} at cp2item an {animation}",
        ]
    elif bare_name == "bl":
        lines = ["scene bl"]
    elif bare_name in {"SmokeBack", "screen SmokeBackground"}:
        lines = ["anime smoke loop keep"]
    elif bare_name.startswith("screen "):
        lines = []
    else:
        character = translate_character_show(name, cue.atl)
        lines = [character] if character else []
    if inline_transition:
        append_transition(lines, inline_transition)
    return lines


def translate_hide(cue: SourceCue, source_file: str) -> list[str]:
    restored = OVERLAY_RESTORES.get((source_file, cue.line))
    if restored is not None:
        return list(restored)

    text = cue.text
    if text == "hide screen SmokeBackground":
        return ["stop anime"]

    name = text[len("hide ") :].strip().split()[0]
    if name == "xiayo":
        return ["hide xcp2"]
    if name == "shioke":
        return ["hide xk"]
    if name == "chen":
        return ["hide ccy"]
    if name == "gonna":
        return ["hide lgcp2"]
    if name == "syozen":
        return ["hide lscp2"]
    if name in ITEM_ALIASES:
        return [f"hide {ITEM_ALIASES[name]}"]
    # Background/CG overlays are replaced by the next scene or cg cue.
    return []


def translate_cues(cues: list[SourceCue], source_file: str) -> list[str]:
    result: list[str] = []
    for cue in cues:
        text = cue.text
        if text.startswith("with "):
            append_transition(result, text[len("with ") :].strip())
        elif text.startswith("scene "):
            if (source_file, cue.line) in ANIME_STOPS_BEFORE_SCENE:
                result.append("stop anime")
            result.extend(translate_scene(text))
        elif text.startswith("show "):
            result.extend(translate_show(cue))
        elif text.startswith("hide "):
            result.extend(translate_hide(cue, source_file))
        elif text.startswith(("play ", "stop ")):
            result.extend(translate_audio(text))
        elif text.startswith("pause"):
            result.extend(translate_pause(text))

    # Consecutive identical engine nodes add no information and can cause
    # needless fades/audio restarts.
    deduplicated: list[str] = []
    for line in result:
        if not deduplicated or deduplicated[-1] != line:
            deduplicated.append(line)
    return deduplicated


def align_anchors(
    source: list[SourceAnchor], target: list[TargetAnchor]
) -> dict[int, int]:
    source_keys = [anchor.key for anchor in source]
    target_keys = [anchor.key for anchor in target]
    matcher = difflib.SequenceMatcher(
        a=source_keys,
        b=target_keys,
        autojunk=False,
    )
    mapping: dict[int, int] = {}
    for source_start, target_start, size in matcher.get_matching_blocks():
        for offset in range(size):
            mapping[source_start + offset] = target_start + offset
    return mapping


def merge_file(
    source_path: Path,
    target_path: Path,
    renpy_character_aliases: set[str],
    renpy_nvl_aliases: set[str],
    saki_character_aliases: set[str],
) -> tuple[str, dict[str, int]]:
    source_anchors = parse_source(source_path)
    original_lines = target_path.read_text(encoding="utf-8").splitlines()
    target_lines = strip_generated(original_lines)
    target_anchors = parse_target(target_lines)
    mapping = align_anchors(source_anchors, target_anchors)

    insertions: dict[int, list[tuple[int, list[str]]]] = {}
    replaced_target_lines: set[int] = set()
    translated_count = 0
    cue_count = 0
    matched_cue_count = 0
    for source_index, source_anchor in enumerate(source_anchors):
        cue_count += len(source_anchor.cues_before)
        translated = translate_cues(source_anchor.cues_before, source_path.name)
        translated_count += len(translated)
        target_index = mapping.get(source_index)
        if target_index is None or not translated:
            continue
        matched_cue_count += len(source_anchor.cues_before)
        target_line_index = target_anchors[target_index].line_index

        # 旧版迁移通常已在当前两个对白锚点之间放过一部分相同节点。
        # 按出现次数移除这些旧节点，再整体写回 Ren'Py 的有序 cue 序列。
        # 不能用 set 逐行去重：例如「放大 -> pause -> 缩小」一旦只删
        # pause，就会把停顿挪到两段动画之外。
        gap_start = (
            target_anchors[target_index - 1].line_index + 1
            if target_index > 0
            else 0
        )
        available_lines: dict[str, list[int]] = {}
        for line_index in range(gap_start, target_line_index):
            available_lines.setdefault(target_lines[line_index], []).append(line_index)
        for generated_line in translated:
            candidates = available_lines.get(generated_line)
            if not candidates:
                continue
            replaced_target_lines.add(candidates.pop(0))

        insertions.setdefault(target_line_index, []).append(
            (source_anchor.line, translated)
        )

    merged: list[str] = []
    for index in range(len(target_lines) + 1):
        for source_line, lines in insertions.get(index, []):
            merged.append(
                f"{GENERATED_START} source={source_path.name}:{source_line}>"
            )
            merged.extend(lines)
            merged.append(GENERATED_END)
        if index < len(target_lines) and index not in replaced_target_lines:
            merged.append(target_lines[index])

    merged, nvl_stats = rebuild_nvlm_blocks(
        source_path,
        merged,
        renpy_character_aliases,
        renpy_nvl_aliases,
        saki_character_aliases,
    )
    output = "\n".join(merged) + "\n"
    stats = {
        "source_anchors": len(source_anchors),
        "matched_anchors": len(mapping),
        "source_cues": cue_count,
        "matched_cues": matched_cue_count,
        "generated_nodes": translated_count,
        **nvl_stats,
    }
    return output, stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--renpy-root", type=Path, default=DEFAULT_RENPY_ROOT)
    parser.add_argument(
        "--renpy-characters",
        type=Path,
        default=DEFAULT_RENPY_CHARACTERS,
    )
    parser.add_argument("--sks-root", type=Path, default=DEFAULT_SKS_ROOT)
    parser.add_argument(
        "--saki-characters",
        type=Path,
        default=DEFAULT_SAKI_CHARACTERS,
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write the deterministic merged scripts (default: report only)",
    )
    args = parser.parse_args()

    totals = {
        "source_anchors": 0,
        "matched_anchors": 0,
        "source_cues": 0,
        "matched_cues": 0,
        "generated_nodes": 0,
        "source_dialogues": 0,
        "target_dialogues": 0,
        "nvl_dialogues": 0,
        "adv_dialogues": 0,
        "nvl_runs": 0,
        "unmatched_dialogues": 0,
        "positional_replacements": 0,
    }
    renpy_character_aliases, renpy_nvl_aliases = parse_renpy_character_kinds(
        args.renpy_characters
    )
    saki_character_aliases = parse_saki_character_aliases(
        args.saki_characters
    )
    changed = 0
    for source_path in sorted(args.renpy_root.glob("cp2_*.rpy")):
        target_path = args.sks_root / f"{source_path.stem}.sks"
        if not target_path.exists():
            print(f"missing target: {target_path}")
            continue
        output, stats = merge_file(
            source_path,
            target_path,
            renpy_character_aliases,
            renpy_nvl_aliases,
            saki_character_aliases,
        )
        old = target_path.read_text(encoding="utf-8")
        if output != old:
            changed += 1
            if args.apply:
                target_path.write_text(output, encoding="utf-8")
        for key, value in stats.items():
            totals[key] += value
        print(
            f"{source_path.name}: anchors "
            f"{stats['matched_anchors']}/{stats['source_anchors']}, cues "
            f"{stats['matched_cues']}/{stats['source_cues']}, "
            f"nodes {stats['generated_nodes']}, dialogue "
            f"ADV {stats['adv_dialogues']} / NVL {stats['nvl_dialogues']} "
            f"in {stats['nvl_runs']} blocks, "
            f"unmatched {stats['unmatched_dialogues']}"
        )

    print(
        "TOTAL: anchors "
        f"{totals['matched_anchors']}/{totals['source_anchors']}, cues "
        f"{totals['matched_cues']}/{totals['source_cues']}, "
        f"nodes {totals['generated_nodes']}, dialogue "
        f"ADV {totals['adv_dialogues']} / NVL {totals['nvl_dialogues']} "
        f"in {totals['nvl_runs']} blocks, "
        f"unmatched {totals['unmatched_dialogues']}, files changed {changed}"
    )
    if not args.apply and changed:
        print("dry run only; pass --apply after reviewing the report")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
