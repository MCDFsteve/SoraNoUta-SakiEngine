"""Exercise build.sh with isolated files and mocked Flutter/Dart executables."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parents[1]
LOADER = Path("lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart")
ORIGINAL_LOADER = "// Existing engine loader must survive every build.\n"
MOCK_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, re, sys
root = pathlib.Path.cwd()
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + '\n')
if pathlib.Path(sys.argv[0]).name == 'dart':
    assert os.environ['MOCK_MODE'] == 'release', 'Showcase precompiled scripts'
    pathlib.Path(sys.argv[sys.argv.index('--output') + 1]).write_text('// MOCK_PRECOMPILED\n')
    sys.exit(0)
args = sys.argv[1:]
if os.environ['MOCK_MODE'] == 'showcase':
    pubspec = (root / 'pubspec.yaml').read_text()
    block = pubspec.split('  assets:', 1)[1].split('  shaders:', 1)[0]
    assert 'default_game.txt' in block
    assert 'Assets/shaders/' in block
    assert not re.search(r'GameScript|sakipak|Assets/(?:fonts|images|music)/', block)
    assert '    - Assets/\n' not in block
    assert '  shaders:\n    - Assets/shaders/sample.frag\n' in pubspec
    assert pubspec.split('  fonts:', 1)[1] == (root / 'original.yaml').read_text().split('  fonts:', 1)[1]
    assert 'return null;' in (pathlib.Path(os.environ['SAKI_ENGINE_PATH']) / os.environ['MOCK_LOADER']).read_text()
if args == ['pub', 'get']:
    sys.exit(int(os.environ.get('FAIL_PUB', '0')))
expected = ['build', 'windows', '--release']
if os.environ['MOCK_MODE'] == 'showcase':
    expected += ['--dart-define=SAKI_SHOW_MODE=true', '--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/FixtureGame']
else:
    assert 'MOCK_PRECOMPILED' in (pathlib.Path(os.environ['SAKI_ENGINE_PATH']) / os.environ['MOCK_LOADER']).read_text()
assert args == expected, args
if os.environ.get('FAIL_BUILD'):
    sys.exit(int(os.environ['FAIL_BUILD']))
output = root / 'build/windows' / os.environ.get('MOCK_ARCH', 'x64') / 'runner/Release'
output.mkdir(parents=True, exist_ok=True)
(output / 'fixture.exe').write_bytes(b'fixture')
'''


def run_fixture(mode="showcase", *, arch="x64", failure=None, explicit=True):
    with tempfile.TemporaryDirectory(prefix="saki-showcase-build-") as temp:
        root = Path(temp)
        game, engine, bin_dir = root / "game", root / "Engine", root / "bin"
        game.mkdir()
        bin_dir.mkdir()
        (engine / "tool").mkdir(parents=True)
        (engine / "tool/sks_compiler.dart").write_text("// mock compiler\n")
        (engine / LOADER).parent.mkdir(parents=True)
        (engine / LOADER).write_text(ORIGINAL_LOADER)
        shutil.copyfile(PROJECT / "build.sh", game / "build.sh")
        pubspec = (PROJECT / "pubspec.yaml").read_text().replace(
            "  fonts:\n",
            "    - Assets/shaders/\n"
            "    - 'Assets/music/' # already external\n"
            "  shaders:\n    - Assets/shaders/sample.frag\n  fonts:\n",
        )
        (game / "pubspec.yaml").write_text(pubspec)
        (game / "original.yaml").write_text(pubspec)
        files = {
            "default_game.txt": "FixtureGame\n",
            "game_config.txt": "title=Fixture\n",
            "icon.png": "icon",
            "Assets/images/backgrounds/sample.png": "image",
            "Assets/music/sample.ogg": "music",
            "Assets/shaders/sample.frag": "shader",
            "Assets/fonts/SourceHanSansCN-Bold.ttf": "font",
            "Assets/fonts/ChillJinshuSongPro_Soft.otf": "font",
            "GameScript/labels/start.sks": 'label start\n"/en Hello/ /jp こんにちは/"\n',
            "GameScript/configs/characters.sks": 'x : "Name" : narrator\n',
            "GameScript_ja/labels/start.sks": 'label start\n"legacy variant"\n',
        }
        for name, content in files.items():
            path = game / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        for name in ["flutter", "dart"]:
            path = bin_dir / name
            path.write_text(MOCK_TOOL)
            path.chmod(0o755)
        env = os.environ | {
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "SAKI_ENGINE_PATH": str(engine),
            "MOCK_LOADER": str(LOADER),
            "MOCK_MODE": mode,
            "MOCK_ARCH": arch,
        }
        if failure:
            env[failure] = "9"
        command = ["bash", "build.sh", "windows"]
        if explicit:
            command.append(mode)
        result = subprocess.run(command, cwd=game, env=env, text=True, capture_output=True)
        assert result.returncode == (9 if failure else 0), result.stdout + result.stderr
        assert (game / "pubspec.yaml").read_text() == pubspec
        assert (engine / LOADER).read_text() == ORIGINAL_LOADER
        calls = [json.loads(line) for line in (game / "calls.jsonl").read_text().splitlines()]
        if mode == "showcase":
            assert not any(call[0] == "dart" for call in calls)
            assert not (game / ".saki_cache/game.sakipak").exists()
            if not failure:
                target = game / "build/windows" / arch / "runner/Release/Game/FixtureGame"
                for name, content in files.items():
                    assert (target / name).read_text() == content, name
        else:
            assert any(call[0] == "dart" for call in calls)
        print(f"Passed: mode={mode}, arch={arch}, failure={failure}, explicit={explicit}")


if __name__ == "__main__":
    run_fixture()
    run_fixture(arch="arm64")
    run_fixture(failure="FAIL_PUB")
    run_fixture(failure="FAIL_BUILD")
    run_fixture("release", explicit=False)
