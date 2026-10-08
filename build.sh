#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_NAME=$(cat "$PROJECT_DIR/default_game.txt" 2>/dev/null | tr -d '\r\n' | xargs || true)
if [ -z "$GAME_NAME" ]; then
  GAME_NAME="$(basename "$PROJECT_DIR")"
fi

is_supported_platform() {
  case "$1" in
    macos|linux|windows|android|ios|web) return 0 ;;
    *) return 1 ;;
  esac
}

platform_display_name() {
  case "$1" in
    macos) echo "macOS" ;;
    linux) echo "Linux" ;;
    windows) echo "Windows" ;;
    android) echo "Android" ;;
    ios) echo "iOS" ;;
    web) echo "Web" ;;
    *) echo "$1" ;;
  esac
}

detect_host_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

choose_platform() {
  local host_platform
  host_platform=$(detect_host_platform)
  local options=()

  case "$host_platform" in
    macos)
      options=(macos ios android web)
      ;;
    linux)
      options=(linux android web)
      ;;
    windows)
      options=(windows android web)
      ;;
    *)
      options=(macos linux windows android ios web)
      ;;
  esac

  local default_index=1
  local i
  for i in "${!options[@]}"; do
    if [ "${options[$i]}" = "$host_platform" ]; then
      default_index=$((i + 1))
      break
    fi
  done

  echo -e "${YELLOW}请选择要构建的平台:${NC}"
  for i in "${!options[@]}"; do
    local idx=$((i + 1))
    local mark=""
    if [ "$idx" -eq "$default_index" ]; then
      mark=" ${BLUE}(默认)${NC}"
    fi
    echo -e "${BLUE}  $idx. $(platform_display_name "${options[$i]}")${mark}${NC}"
  done
  echo ""
  echo -ne "${YELLOW}请输入平台编号 (默认 ${default_index}): ${NC}"
  read -r platform_choice

  if [ -z "$platform_choice" ]; then
    platform_choice="$default_index"
  fi

  if ! [[ "$platform_choice" =~ ^[0-9]+$ ]] ||
     [ "$platform_choice" -lt 1 ] ||
     [ "$platform_choice" -gt "${#options[@]}" ]; then
    echo -e "${RED}错误: 无效的平台编号 ${platform_choice}${NC}"
    exit 1
  fi

  PLATFORM="${options[$((platform_choice - 1))]}"
}

detect_engine_dir() {
  local candidates=()

  if [ -n "${SAKI_ENGINE_PATH:-}" ]; then
    candidates+=("$SAKI_ENGINE_PATH")
  fi

  candidates+=(
    "$PROJECT_DIR/Engine"
    "$PROJECT_DIR/../Engine"
    "$PROJECT_DIR/../../Engine"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate/tool/sks_compiler.dart" ] &&
       [ -f "$candidate/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  done

  return 1
}

PLATFORM="${1:-}"
BUILD_MODE="${2:-release}"
if [ -z "$PLATFORM" ]; then
  choose_platform
elif ! is_supported_platform "$PLATFORM"; then
  echo -e "${RED}错误: 不支持的平台 '$PLATFORM'。${NC}"
  exit 1
fi

case "$BUILD_MODE" in
  release) ;;
  showcase)
    if [ "$PLATFORM" != "windows" ]; then
      echo -e "${RED}错误: showcase 目前仅支持 Windows 构建。${NC}"
      exit 1
    fi
    ;;
  *)
    echo -e "${RED}错误: 不支持的构建模式 '$BUILD_MODE'，请选择 release 或 showcase。${NC}"
    exit 1
    ;;
esac

ENGINE_DIR=$(detect_engine_dir || true)
if [ -z "$ENGINE_DIR" ]; then
  echo -e "${RED}错误: 未找到可用的 Engine 目录。${NC}"
  echo -e "${YELLOW}请确认以下任一路径存在并有效:${NC}"
  echo "  - SAKI_ENGINE_PATH"
  echo "  - $PROJECT_DIR/Engine"
  echo "  - $PROJECT_DIR/../Engine"
  echo "  - $PROJECT_DIR/../../Engine"
  exit 1
fi

ENGINE_COMPILED_LOADER="$ENGINE_DIR/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart"
GAME_SKS_CACHE_DIR="$PROJECT_DIR/.saki_cache"
GAME_SKS_BUNDLE_FILE="$GAME_SKS_CACHE_DIR/compiled_sks_bundle.g.dart"
GAME_SKS_COMPILER_FILE="$GAME_SKS_CACHE_DIR/sks_compiler.dart"
GAME_PUBSPEC_FILE="$PROJECT_DIR/pubspec.yaml"
GAME_PUBSPEC_BACKUP_FILE="$GAME_SKS_CACHE_DIR/pubspec.yaml.backup"
ENGINE_COMPILED_BACKUP_FILE="$GAME_SKS_CACHE_DIR/engine_compiled_loader.backup"

write_empty_compiled_loader() {
  cat > "$ENGINE_COMPILED_LOADER" <<'LOADER_EOF'
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';

CompiledSksBundle? loadGeneratedCompiledSksBundle() {
  return null;
}
LOADER_EOF
}

prepare_showcase_pubspec_assets() {
  cp -f "$GAME_PUBSPEC_FILE" "$GAME_PUBSPEC_BACKUP_FILE"
  # Match Launcher/lib/showcase_assets.dart: media/scripts live beside the exe;
  # Flutter must still compile its declared fonts, shaders and bootstrap assets.
  awk -v sq="'" '
    function flush_assets() {
      print has_entries ? assets_header : "  assets: []"
      for (i = 1; i <= kept_count; i++) print kept[i]
      in_assets = 0
    }
    {
      sub(/\r$/, "")
      if ($0 ~ /^  assets:[[:space:]]*$/) {
        found_assets = 1
        in_assets = 1
        assets_header = $0
        next
      }
      if (in_assets && ($0 ~ /^    / || $0 ~ /^[[:space:]]*$/)) {
        if ($0 ~ /^    -[[:space:]]+/) {
          path = $0
          sub(/^    -[[:space:]]+/, "", path)
          sub(/[[:space:]]+#.*$/, "", path)
          sub(/[[:space:]]+$/, "", path)
          first = substr(path, 1, 1)
          if ((first == "\"" || first == sq) &&
              substr(path, length(path), 1) == first) {
            path = substr(path, 2, length(path) - 2)
          }
          gsub(/\\/, "/", path)
          sub(/^\.\//, "", path)
          path = tolower(path)
          is_shader = path ~ /^assets\/shaders\//
          if (path == "assets" || (path ~ /^assets\// && !is_shader) ||
              path ~ /^gamescript(_|\/|$)/ || path ~ /^\.saki_cache\/?$/ ||
              path ~ /\.sakipak$/) next
          has_entries = 1
        } else if ($0 !~ /^[[:space:]]*(#.*)?$/) {
          print "演出资源清单仅支持字符串路径" > "/dev/stderr"
          invalid = 1
          exit 1
        }
        kept[++kept_count] = $0
        next
      }
      if (in_assets) flush_assets()
      print
    }
    END {
      if (invalid) exit 1
      if (!found_assets) {
        print "pubspec.yaml 未找到 flutter/assets 段" > "/dev/stderr"
        exit 1
      }
      if (in_assets) flush_assets()
    }
  ' "$GAME_PUBSPEC_BACKUP_FILE" > "$GAME_SKS_CACHE_DIR/pubspec.yaml.temp"
  mv -f "$GAME_SKS_CACHE_DIR/pubspec.yaml.temp" "$GAME_PUBSPEC_FILE"
}

stage_showcase_game_directory() {
  local output_dirs=()
  local candidate
  for candidate in "$PROJECT_DIR"/build/windows/*/runner/Release \
                   "$PROJECT_DIR/build/windows/runner/Release"; do
    [ -d "$candidate" ] && output_dirs+=("$candidate")
  done
  if [ "${#output_dirs[@]}" -ne 1 ]; then
    echo -e "${RED}错误: 无法唯一确定 Windows Release 目录，请先清理旧 Windows 构建。${NC}"
    return 1
  fi
  if [ ! -d "$PROJECT_DIR/Assets" ] || [ ! -d "$PROJECT_DIR/GameScript" ]; then
    echo -e "${RED}错误: 演出构建需要 Assets 和 GameScript 目录。${NC}"
    return 1
  fi
  local target="${output_dirs[0]}/Game/$GAME_NAME"
  rm -rf "$target"
  mkdir -p "$target"
  cp -R "$PROJECT_DIR/Assets" "$target/Assets"
  for candidate in "$PROJECT_DIR/GameScript" "$PROJECT_DIR"/GameScript_*; do
    [ -d "$candidate" ] || continue
    cp -R "$candidate" "$target/$(basename "$candidate")"
  done
  for candidate in game_config.txt default_game.txt icon.png; do
    [ -f "$PROJECT_DIR/$candidate" ] || continue
    cp -f "$PROJECT_DIR/$candidate" "$target/$candidate"
  done
  echo -e "${GREEN}演出资源已复制: $target${NC}"
}

prepare_release_pubspec_assets() {
  mkdir -p "$GAME_SKS_CACHE_DIR"
  cp -f "$GAME_PUBSPEC_FILE" "$GAME_PUBSPEC_BACKUP_FILE"

  local assets_start_line
  assets_start_line=$(grep -n -E "^  assets:\s*$" "$GAME_PUBSPEC_BACKUP_FILE" | head -1 | cut -d: -f1)
  if [ -z "${assets_start_line:-}" ]; then
    echo -e "${RED}错误: pubspec.yaml 未找到 flutter/assets 段${NC}"
    exit 1
  fi

  local assets_end_line="$assets_start_line"
  local total_lines
  total_lines=$(wc -l < "$GAME_PUBSPEC_BACKUP_FILE" | xargs)
  while [ "$assets_end_line" -lt "$total_lines" ]; do
    local next_line_num=$((assets_end_line + 1))
    local line
    line=$(sed -n "${next_line_num}p" "$GAME_PUBSPEC_BACKUP_FILE")
    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]{4}-[[:space:]]+ ]]; then
      assets_end_line="$next_line_num"
      continue
    fi
    break
  done

  local raw_assets_file="$GAME_SKS_CACHE_DIR/raw_assets_entries.txt"
  local expanded_assets_file="$GAME_SKS_CACHE_DIR/expanded_assets_entries.txt"
  local unique_assets_file="$GAME_SKS_CACHE_DIR/unique_assets_entries.txt"
  local temp_pubspec="$GAME_SKS_CACHE_DIR/pubspec.yaml.temp"

  sed -n "$((assets_start_line + 1)),$((assets_end_line))p" "$GAME_PUBSPEC_BACKUP_FILE" \
    | sed -n -E "s/^[[:space:]]{4}-[[:space:]]+(.+)$/\1/p" \
    | sed -E "s/[[:space:]]+#.*$//" \
    | sed -E "s/^['\"](.*)['\"]$/\1/" \
    > "$raw_assets_file"

  : > "$expanded_assets_file"
  while IFS= read -r entry; do
    entry=$(echo "$entry" | xargs)
    [ -n "$entry" ] || continue

    case "$entry" in
      GameScript|GameScript/|GameScript/*|GameScript_*)
        continue
        ;;
    esac

    local normalized="${entry%/}"
    local full_path="$PROJECT_DIR/$normalized"

    if [ -d "$full_path" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        local relative="${file_path#$PROJECT_DIR/}"
        relative=${relative//\\//}
        case "$relative" in
          GameScript/*|GameScript_*)
            continue
            ;;
        esac
        echo "$relative" >> "$expanded_assets_file"
      done < <(find "$full_path" -type f ! -name '.DS_Store' | sort)
    elif [ -f "$full_path" ]; then
      echo "$normalized" >> "$expanded_assets_file"
    else
      echo -e "${YELLOW}警告: 资源路径不存在，已跳过: $entry${NC}"
    fi
  done < "$raw_assets_file"

  awk 'NF && !seen[$0]++' "$expanded_assets_file" > "$unique_assets_file"

  local expanded_count
  expanded_count=$(wc -l < "$unique_assets_file" | xargs)
  if [ "$expanded_count" -eq 0 ]; then
    echo -e "${RED}错误: 发布资源清单为空，已中止构建。${NC}"
    exit 1
  fi

  local image_count
  image_count=$(grep -E -i "^Assets/images/.*\.(png|jpg|jpeg|gif|bmp|webp|avif|mp4|mov|avi|mkv|webm)$" \
    "$unique_assets_file" | wc -l | xargs)
  if grep -q -E "^Assets/?$" "$raw_assets_file" && [ "$image_count" -eq 0 ]; then
    echo -e "${RED}错误: 检测到配置了 Assets/，但展开后没有任何 Assets/images 资源。${NC}"
    echo -e "${RED}为防止发布包缺少美术素材，已中止构建。${NC}"
    exit 1
  fi

  head -n "$assets_start_line" "$GAME_PUBSPEC_BACKUP_FILE" > "$temp_pubspec"
  while IFS= read -r asset_file; do
    [ -n "$asset_file" ] || continue
    echo "    - $asset_file" >> "$temp_pubspec"
  done < "$unique_assets_file"
  tail -n "+$((assets_end_line + 1))" "$GAME_PUBSPEC_BACKUP_FILE" >> "$temp_pubspec"

  mv -f "$temp_pubspec" "$GAME_PUBSPEC_FILE"
  echo -e "${YELLOW}已更新发布资源清单：总计 ${expanded_count} 项，图片/视频 ${image_count} 项，排除 GameScript*.sks${NC}"
}

restore_game_pubspec() {
  if [ -f "$GAME_PUBSPEC_BACKUP_FILE" ]; then
    mv -f "$GAME_PUBSPEC_BACKUP_FILE" "$GAME_PUBSPEC_FILE"
  fi
}

cleanup_on_exit() {
  if [ -f "$ENGINE_COMPILED_BACKUP_FILE" ]; then
    mv -f "$ENGINE_COMPILED_BACKUP_FILE" "$ENGINE_COMPILED_LOADER"
  fi
  restore_game_pubspec
}

mkdir -p "$GAME_SKS_CACHE_DIR"
cp -f "$ENGINE_COMPILED_LOADER" "$ENGINE_COMPILED_BACKUP_FILE"
trap cleanup_on_exit EXIT

echo -e "${GREEN}游戏项目: $GAME_NAME${NC}"
echo -e "${GREEN}目标平台: $(platform_display_name "$PLATFORM")${NC}"
echo -e "${GREEN}构建模式: $BUILD_MODE${NC}"
echo -e "${BLUE}Engine目录: $ENGINE_DIR${NC}"

cd "$PROJECT_DIR"

if [ "$BUILD_MODE" = "showcase" ]; then
  echo -e "${YELLOW}演出模式：保留原始 GameScript，媒体和剧本从外部 Game 目录读取。${NC}"
  write_empty_compiled_loader
  prepare_showcase_pubspec_assets
  flutter pub get
  flutter build windows --release \
    --dart-define=SAKI_SHOW_MODE=true \
    "--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/$GAME_NAME"
  stage_showcase_game_directory
  echo -e "${GREEN}构建完成: $PLATFORM ($BUILD_MODE)${NC}"
  exit 0
fi

echo -e "${YELLOW}准备脚本编译环境（首次依赖解析）...${NC}"
flutter pub get

echo -e "${YELLOW}正在预编译 .sks 脚本为 Dart...${NC}"
mkdir -p "$GAME_SKS_CACHE_DIR"
# Dart 3.12 on Windows refuses to use `pub run` for scripts associated with a
# path dependency. Invoke the VM with the package configuration produced above
# so package:sakiengine resolves without going through that restricted command.
cp -f "$ENGINE_DIR/tool/sks_compiler.dart" "$GAME_SKS_COMPILER_FILE"
dart --packages="$PROJECT_DIR/.dart_tool/package_config.json" \
  "$GAME_SKS_COMPILER_FILE" \
  --game-dir "$PROJECT_DIR" \
  --output "$GAME_SKS_BUNDLE_FILE" \
  --game-name "$GAME_NAME"

if [ ! -f "$GAME_SKS_BUNDLE_FILE" ]; then
  echo -e "${RED}错误: 预编译产物不存在: $GAME_SKS_BUNDLE_FILE${NC}"
  exit 1
fi

cp -f "$GAME_SKS_BUNDLE_FILE" "$ENGINE_COMPILED_LOADER"

echo -e "${YELLOW}正在生成发布资源清单...${NC}"
prepare_release_pubspec_assets

echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

echo -e "${YELLOW}正在构建 $PLATFORM ...${NC}"
case "$PLATFORM" in
  macos)
    flutter build macos --release
    ;;
  linux)
    flutter build linux --release
    ;;
  windows)
    flutter build windows --release
    ;;
  android)
    flutter build apk --release --target-platform android-arm64
    ;;
  ios)
    (cd ios && pod install)
    flutter build ios --release --no-codesign
    ;;
  web)
    flutter build web --release
    ;;
  *)
    echo -e "${RED}错误: 不支持的平台 '$PLATFORM'。${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}构建完成: $PLATFORM${NC}"
