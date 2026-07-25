#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
xiayo_source="${1:-/Library/Afolder/RenpyProject/SoraNoUta/素材/hito/xiayo/pose3}"
shioke_source="${2:-/Library/Afolder/RenpyProject/SoraNoUta/素材/hito/shioke}"
chapter2_source="${3:-/Library/Afolder/项目/空之歌/cg和角色}"
renpy_game_source="${4:-/Library/Afolder/RenpyProject/SoraNoUta/game}"

if [[ ! -f "$shioke_source/body1.png" && -d "$shioke_source/pose1" ]]; then
  shioke_source="$shioke_source/pose1"
fi

character_pose_dir="$project_root/Assets/images/characters/story2/pose"
character_expression_dir="$project_root/Assets/images/characters/story2/emoji"
cg_root="$project_root/Assets/images/cg"
temporary_dir="$(mktemp -d /tmp/soranouta-chapter2-assets.XXXXXX)"

cleanup() {
  case "$temporary_dir" in
    /tmp/soranouta-chapter2-assets.*) rm -rf "$temporary_dir" ;;
  esac
}
trap cleanup EXIT

for command_name in magick cwebp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

for source_dir in \
  "$xiayo_source" \
  "$shioke_source" \
  "$chapter2_source" \
  "$renpy_game_source"; do
  if [[ ! -d "$source_dir" ]]; then
    echo "Missing source directory: $source_dir" >&2
    exit 1
  fi
done

mkdir -p "$character_pose_dir" "$character_expression_dir" "$cg_root"

bash "$project_root/tools/convert_smoke_animation.sh" \
  "$renpy_game_source/images/anime/smoke.webm" \
  "$project_root/Assets/movies/smoke.webp"

encode_webp() {
  local input_file="$1"
  local output_file="$2"
  mkdir -p "$(dirname "$output_file")"
  # 分层资源必须无损：有损底图与独立编码的透明差分在交界处会产生块边，
  # 切换表情时就会表现成轻微扭曲或闪烁。
  cwebp -quiet -lossless -z 6 -exact "$input_file" -o "$output_file"
}

encode_visual_webp() {
  local input_file="$1"
  local output_file="$2"
  local intermediate_png="$temporary_dir/$(basename "$output_file" .webp).png"
  magick "$input_file" "$intermediate_png"
  encode_webp "$intermediate_png" "$output_file"
}

make_transparent_canvas() {
  local width="$1"
  local height="$2"
  local output_file="$3"
  magick -size "${width}x${height}" xc:none "$output_file"
}

make_difference_overlay() {
  local base_file="$1"
  local variant_file="$2"
  local output_file="$3"
  local overlay_png="$temporary_dir/difference-overlay.png"

  magick \
    "$variant_file" \
    \( "$variant_file" "$base_file" -compose difference -composite \
      -colorspace gray -threshold 0 \) \
    -alpha off -compose CopyOpacity -composite \
    "$overlay_png"
  encode_webp "$overlay_png" "$output_file"
}

# 第二章实际分镜仍会调用的 Ren'Py 背景。统一改为语义化文件名，
# 与 SakiEngine 中以空格书写、运行时转连字符的解析规则保持一致。
renpy_background_dir="$renpy_game_source/images/background"
declare -a chapter2_backgrounds=(
  "hayasi.avif:hayasi.webp"
  "ike.avif:ike.webp"
  "class.avif:class.webp"
  "store.avif:store.webp"
  "schoolgate.avif:schoolgate.webp"
  "schoolgate 17.avif:schoolgate-yuu.webp"
  "ground.avif:ground.webp"
  "classdoor.avif:classdoor.webp"
  "hasi 17.avif:hasi-yuu.webp"
  "shiokehome.avif:shiokehome.webp"
  "shiokehome 17.avif:shiokehome-yuu.webp"
  "shiokegate.avif:shiokegate.webp"
  "shiokegate17.avif:shiokegate17.webp"
  "oka 17.avif:oka-yuu.webp"
  "lab.avif:lab.webp"
  "road 7.avif:road-asa.webp"
)
for background_mapping in "${chapter2_backgrounds[@]}"; do
  IFS=: read -r source_name output_name <<<"$background_mapping"
  encode_visual_webp \
    "$renpy_background_dir/$source_name" \
    "$project_root/Assets/images/backgrounds/$output_name"
done

begin_cg_group() {
  local resource_id="$1"
  local base_file="$2"
  local first_variant="$3"
  local output_dir="$cg_root/$resource_id"
  local empty_png="$temporary_dir/empty-cg.png"

  mkdir -p "$output_dir"
  encode_webp "$base_file" "$output_dir/$resource_id-pose1.webp"
  make_transparent_canvas 1920 1080 "$empty_png"
  encode_webp "$empty_png" "$output_dir/$resource_id-$first_variant.webp"
}

add_cg_difference() {
  local resource_id="$1"
  local base_file="$2"
  local variant_file="$3"
  local variant_id="$4"
  make_difference_overlay \
    "$base_file" \
    "$variant_file" \
    "$cg_root/$resource_id/$resource_id-$variant_id.webp"
}

compose_over() {
  local output_file="$1"
  shift
  local layers=("$@")
  local command=(magick "${layers[0]}")
  local index
  for ((index = 1; index < ${#layers[@]}; index++)); do
    command+=("${layers[$index]}" -compose over -composite)
  done
  command+=("$output_file")
  "${command[@]}"
}

compose_multiply() {
  local output_file="$1"
  shift
  local layers=("$@")
  local command=(magick "${layers[0]}")
  local index
  for ((index = 1; index < ${#layers[@]}; index++)); do
    command+=("${layers[$index]}" -compose multiply -composite)
  done
  command+=("$output_file")
  "${command[@]}"
}

# 夏悠（第二章）：body 作为 pose 底层，arm 作为 pose-foreground。
# 这样表情仍由 SakiEngine 原生切换，手部也能正确覆盖在脸部上方。
encode_webp "$xiayo_source/body.png" "$temporary_dir/xiayo2-body.webp"
for pose_number in 1 2 3 4 6; do
  cp "$temporary_dir/xiayo2-body.webp" \
    "$character_pose_dir/xiayo2-pose${pose_number}.webp"
done

for arm_number in 1 2 3 4; do
  encode_webp \
    "$xiayo_source/arm${arm_number}.png" \
    "$character_pose_dir/xiayo2-pose${arm_number}-foreground.webp"
done

# arm5 + arm6 拼接后的手臂与身体存在明显错位，pose5 已停用。
encode_webp \
  "$xiayo_source/arm7.png" \
  "$character_pose_dir/xiayo2-pose6-foreground.webp"

casual_source_dir="$chapter2_source/夏悠第二章便装"
casual_sources=(
  "$casual_source_dir/新衣服克拉斯呀.png"
  "$casual_source_dir/新衣服克拉斯呀2.png"
  "$casual_source_dir/新衣服克拉斯呀3.png"
  "$casual_source_dir/新衣服克拉斯呀4.png"
  "$casual_source_dir/新衣服克拉斯呀5.png"
  "$casual_source_dir/新衣服克拉斯呀6.png"
  "$casual_source_dir/新衣服克拉斯呀7.png"
  "$casual_source_dir/新衣服克拉斯呀8.png"
  "$casual_source_dir/新衣服克拉斯呀9.png"
)
for index in "${!casual_sources[@]}"; do
  pose_number=$((index + 7))
  encode_webp \
    "${casual_sources[$index]}" \
    "$character_pose_dir/xiayo2-pose${pose_number}.webp"
done

for expression_file in "$xiayo_source"/*.png; do
  expression_name="$(basename "$expression_file" .png)"
  case "$expression_name" in
    body|arm[0-9]*) continue ;;
  esac
  expression_source="$expression_file"
  if [[ "$expression_name" == "kirakira" ]]; then
    # pose3/kirakira.png 是目录中残留的第一章整头差分，会把第二章脸和
    # 发型一起覆盖掉。pose3/star.png 才是同一套新版立绘中语义一致的
    # “闪闪发光的眼睛 + 开心张嘴”，保留 kirakira 资源名供剧本调用。
    expression_source="$xiayo_source/star.png"
  fi
  encode_webp \
    "$expression_source" \
    "$character_expression_dir/xiayo2-$expression_name.webp"
done

declare -a xiayo_combined_expressions=(
  "happy2:kuraikaop:happy2-kuraikaop"
  "smile2:kuraikaop:smile2-kuraikaop"
  "unhappy:kuraikaop:unhappy-kuraikaop"
  "shy4:shyp:shy4-shyp"
  "shy5:shyp:shy5-shyp"
  "think:nani:think-nani"
  "fusigi:nani:fusigi-nani"
  "akireta3:kuraikaop:akireta3-kuraikaop"
  "unhappy:nande:unhappy-nande"
  "think:kuraikaop:think-kuraikaop"
  "think2:nande:think2-nande"
  "happy:nani:happy-nani"
  "kowa:nande:kowa-nande"
  "tameiki:nani:tameiki-nani"
  "ochikomu:kuraikaop:ochikomu-kuraikaop"
)
for combination in "${xiayo_combined_expressions[@]}"; do
  IFS=: read -r base_expression plugin_expression output_expression \
    <<<"$combination"
  combined_png="$temporary_dir/xiayo-$output_expression.png"
  compose_over \
    "$combined_png" \
    "$xiayo_source/$base_expression.png" \
    "$xiayo_source/$plugin_expression.png"
  encode_webp \
    "$combined_png" \
    "$character_expression_dir/xiayo2-$output_expression.webp"
done

# 两个旧剧本兼容名在 pose3 素材中没有独立差分，用语义上最接近的现有表情兜齐，
# 避免运行时退回到目录中的随机首项。
cp \
  "$character_expression_dir/xiayo2-tameiki2.webp" \
  "$character_expression_dir/xiayo2-think3.webp"
cp \
  "$character_expression_dir/xiayo2-unhappy.webp" \
  "$character_expression_dir/xiayo2-nan3.webp"
cp \
  "$character_expression_dir/xiayo2-shy1.webp" \
  "$character_expression_dir/xiayo2-shy.webp"

# 萧可：同样保留 body -> face -> arm 的原作图层顺序。
for pose_number in 1 2 3; do
  encode_webp \
    "$shioke_source/body1.png" \
    "$character_pose_dir/shioke-pose${pose_number}.webp"
  encode_webp \
    "$shioke_source/arm${pose_number}.png" \
    "$character_pose_dir/shioke-pose${pose_number}-foreground.webp"
done
encode_webp \
  "$shioke_source/body3.png" \
  "$character_pose_dir/shioke-pose4.webp"
encode_webp \
  "$shioke_source/arm1.png" \
  "$character_pose_dir/shioke-pose4-foreground.webp"

for expression_file in "$shioke_source"/*.png; do
  expression_name="$(basename "$expression_file" .png)"
  case "$expression_name" in
    body[0-9]*|arm[0-9]*|手[0-9]*|普通|皱眉|睁眼微笑) continue ;;
  esac
  encode_webp \
    "$expression_file" \
    "$character_expression_dir/shioke-$expression_name.webp"
done
empty_character_png="$temporary_dir/empty-character.png"
make_transparent_canvas 1080 1920 "$empty_character_png"
encode_webp \
  "$empty_character_png" \
  "$character_expression_dir/shioke-empty.webp"

# 陈雏莺：源文件已经是四个完整身体姿势，表情仍保持独立透明层。
chen_source="$chapter2_source/陈雏莺立绘"
chen_pose_sources=(
  "$chen_source/叉手.png"
  "$chen_source/双手抱头.png"
  "$chen_source/投降.png"
  "$chen_source/无表情.png"
)
for index in "${!chen_pose_sources[@]}"; do
  pose_number=$((index + 1))
  encode_webp \
    "${chen_pose_sources[$index]}" \
    "$character_pose_dir/chen-pose${pose_number}.webp"
done

declare -a chen_expressions=(
  "兴奋:wakuwaku"
  "叹气:tameiki"
  "得意:doya"
  "微笑:smile"
  "思考:think"
  "惊讶:odoroki"
  "更生气:ikari2"
  "热血1:moeru"
  "热血2:moeru2"
  "狂气:youki"
  "生气:ikari"
  "观察:miru"
)
for mapping in "${chen_expressions[@]}"; do
  IFS=: read -r source_name output_name <<<"$mapping"
  encode_webp \
    "$chen_source/表情/$source_name.png" \
    "$character_expression_dir/chen-$output_name.webp"
done
cp \
  "$character_expression_dir/chen-smile.webp" \
  "$character_expression_dir/chen-happy.webp"
# 新素材包少了剧本实际调用的“疑惑”差分，沿用 Ren'Py 成品中的同坐标层。
encode_visual_webp \
  "$renpy_game_source/images/hito/chen/pose1/nani.avif" \
  "$character_expression_dir/chen-nani.webp"

# 第二章山路问路的两位旅人使用 Ren'Py 中已经完成的全身立绘。
ijin_source="$renpy_game_source/images/hito/ijin"
encode_webp \
  "$ijin_source/pose1/ijin pose1.png" \
  "$character_pose_dir/ijin-pose1.webp"
encode_webp \
  "$ijin_source/pose2/ijin pose2.png" \
  "$character_pose_dir/ijin-pose2.webp"
ijin_empty_expression="$temporary_dir/ijin-empty-expression.png"
make_transparent_canvas 1080 1920 "$ijin_empty_expression"
encode_webp \
  "$ijin_empty_expression" \
  "$character_expression_dir/ijin-normal.webp"

# 李宫娜、刘守真的第二章立绘尚未交付。这里有意使用全透明图层，
# 仅为分镜、站位和动画提供稳定资源挂点；不是临时替代画，也不会
# 把第一章造型误当成第二章成品。画师交付后原路径覆盖即可生效。
future_character_png="$temporary_dir/future-character-placeholder.png"
make_transparent_canvas 1080 1920 "$future_character_png"
for resource_id in gonna2 syozen2; do
  for pose_number in 1 2 3; do
    encode_webp \
      "$future_character_png" \
      "$character_pose_dir/${resource_id}-pose${pose_number}.webp"
  done
done
for expression_name in neutral angry2 happy hen odoroki satoko tameiki think what; do
  encode_webp \
    "$future_character_png" \
    "$character_expression_dir/gonna2-${expression_name}.webp"
done
for expression_name in neutral happy konoyarou magao odoroki sabishii think; do
  encode_webp \
    "$future_character_png" \
    "$character_expression_dir/syozen2-${expression_name}.webp"
done

# 完整帧 CG 转为 pose1 + 透明像素差分，沿用 SakiEngine 的原生 CG 合成器。
pond_source="$chapter2_source/夏悠cg1-水池洗脚"
begin_cg_group "cg_cp2_pond" "$pond_source/初试.png" "1"
add_cg_difference "cg_cp2_pond" "$pond_source/初试.png" "$pond_source/开心.png" "2"
add_cg_difference "cg_cp2_pond" "$pond_source/初试.png" "$pond_source/微笑.png" "3"
add_cg_difference "cg_cp2_pond" "$pond_source/初试.png" "$pond_source/着凉.png" "4"

moto_source="$chapter2_source/第二章cg2-坐摩托"
begin_cg_group "cgmoto" "$moto_source/三人行.png" "1"
add_cg_difference "cgmoto" "$moto_source/三人行.png" "$moto_source/三人行2.png" "2"

cat_source="$chapter2_source/猫咪-三人看猫咪"
begin_cg_group "shincg3" "$cat_source/小猫咪.png" "1"
for variant_number in 2 3 4; do
  add_cg_difference \
    "shincg3" \
    "$cat_source/小猫咪.png" \
    "$cat_source/小猫咪${variant_number}.png" \
    "$variant_number"
done

reading_source="$chapter2_source/看书-放学路上夏悠看书"
reading_base="$reading_source/看书低垂.png"
begin_cg_group "shincg5" "$reading_base" "1"
add_cg_difference "shincg5" "$reading_base" "$reading_source/看书惊讶.png" "2"
add_cg_difference "shincg5" "$reading_base" "$reading_source/看书生气.png" "3"
add_cg_difference "shincg5" "$reading_base" "$reading_source/看书.png" "4"
add_cg_difference "shincg5" "$reading_base" "$reading_source/看书叹气.png" "5"
add_cg_difference "shincg5" "$reading_base" "$reading_source/看书无奈.png" "6"

dream_source="$chapter2_source/白日梦-萧可站在十字路口/梦.png"
begin_cg_group "shincg6" "$dream_source" "1"

turn_source="$chapter2_source/回眸-夏悠回眸"
begin_cg_group "shincg9" "$turn_source/回眸.png" "1"
add_cg_difference "shincg9" "$turn_source/回眸.png" "$turn_source/回眸闭眼.png" "2"
add_cg_difference \
  "shincg9" \
  "$turn_source/回眸.png" \
  "$turn_source/回眸闭眼无泪花.png" \
  "3"
add_cg_difference \
  "shincg9" \
  "$turn_source/回眸.png" \
  "$turn_source/回眸睁眼泪花.png" \
  "4"

embrace_source="$chapter2_source/双人-萧可抱着夏悠哭.png"
begin_cg_group "shincg9_embrace" "$embrace_source" "1"

reunion_source="$chapter2_source/二人对峙-穿越后萧可和林澄再次相见"
reunion_base="$reunion_source/二人对峙.png"
begin_cg_group "shincg10" "$reunion_base" "2"
add_cg_difference "shincg10" "$reunion_base" "$reunion_source/二人对峙3.png" "3"
add_cg_difference "shincg10" "$reunion_base" "$reunion_source/二人对峙2.png" "4"

sunset_source="$chapter2_source/黄昏-萧可和林澄坐在山头/黄昏结局.png"
begin_cg_group "shincg11" "$sunset_source" "1"

# 趴桌 CG：源文件是透明眼、嘴插件，预合成为剧本中的 1—11 号差分。
sleep_source="$chapter2_source/睡觉-萧可趴桌子上"
sleep_base="$sleep_source/睡觉.png"
sleep_variants=()
for variant_number in $(seq 1 11); do
  sleep_variants[$variant_number]="$temporary_dir/shincg4-$variant_number.png"
done
compose_over "${sleep_variants[1]}" "$sleep_base" "$sleep_source/瞪眼.png" "$sleep_source/不高兴嘴.png"
compose_over "${sleep_variants[2]}" "$sleep_base" "$sleep_source/眯眼.png" "$sleep_source/闭嘴.png"
compose_over "${sleep_variants[3]}" "$sleep_base" "$sleep_source/黑脸.png" "$sleep_source/不高兴嘴.png"
compose_over "${sleep_variants[4]}" "$sleep_base" "$sleep_source/眯眼.png" "$sleep_source/叹气嘴.png"
compose_over "${sleep_variants[5]}" "$sleep_base" "$sleep_source/鱿鱼.png"
compose_over "${sleep_variants[6]}" "$sleep_base" "$sleep_source/瞪眼.png" "$sleep_source/叹气嘴.png"
compose_over "${sleep_variants[7]}" "$sleep_base" "$sleep_source/闭眼.png" "$sleep_source/叹气嘴.png"
compose_over "${sleep_variants[8]}" "$sleep_base" "$sleep_source/闭眼.png" "$sleep_source/闭嘴.png"
compose_over "${sleep_variants[9]}" "$sleep_base" "$sleep_source/瞪眼.png" "$sleep_source/闭嘴.png"
compose_over "${sleep_variants[10]}" "$sleep_base" "$sleep_source/眯眼.png" "$sleep_source/闭嘴.png"
compose_over "${sleep_variants[11]}" "$sleep_base" "$sleep_source/惊讶眼.png" "$sleep_source/惊讶嘴.png"
begin_cg_group "shincg4" "${sleep_variants[1]}" "1"
for variant_number in $(seq 2 11); do
  add_cg_difference \
    "shincg4" \
    "${sleep_variants[1]}" \
    "${sleep_variants[$variant_number]}" \
    "$variant_number"
done
encode_webp "$sleep_base" "$cg_root/shincg4/shincg4-empty.webp"

# 家门口 CG：眼、嘴素材是白底乘算层，先按原绘制方式组合，再做透明差分。
door_source="$chapter2_source/门-萧可家门口"
door_rest="$door_source/门.放手.png"
door_phone="$door_source/门.举手.png"
door_variants=()
for variant_number in $(seq 1 12); do
  door_variants[$variant_number]="$temporary_dir/shincg7-$variant_number.png"
done
compose_multiply "${door_variants[1]}" "$door_rest" "$door_source/门.普通眼.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[2]}" "$door_rest" "$door_source/门.眼微开.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[3]}" "$door_rest" "$door_source/门.普通眼.png" "$door_source/门.皱眉插件.png" "$door_source/门.嘴2.png"
compose_multiply "${door_variants[4]}" "$door_rest" "$door_source/门.笑眼.png" "$door_source/门.笑.png"
compose_multiply "${door_variants[5]}" "$door_rest" "$door_source/门.普通眼.png" "$door_source/门.嘴1.png" "$door_source/门.脸红插件.png"
compose_multiply "${door_variants[6]}" "$door_rest" "$door_source/门.向上看.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[7]}" "$door_rest" "$door_source/门.眉.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[8]}" "$door_phone" "$door_source/门.普通眼.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[9]}" "$door_rest" "$door_source/门.黑脸表情.png" "$door_source/门.普通眼.png" "$door_source/门.皱眉插件.png" "$door_source/门.嘴2.png"
compose_multiply "${door_variants[10]}" "$door_rest" "$door_source/门.黑脸表情.png" "$door_source/门.普通眼.png" "$door_source/门.泪花.png" "$door_source/门.嘴1.png"
compose_multiply "${door_variants[11]}" "$door_rest" "$door_source/门.黑脸表情.png" "$door_source/门.普通眼.png" "$door_source/门.泪花.png" "$door_source/门.慌张嘴.png"
compose_multiply "${door_variants[12]}" "$door_rest" "$door_source/门.哭哭.png" "$door_source/门.慌张嘴.png"
begin_cg_group "shincg7" "${door_variants[1]}" "1"
for variant_number in $(seq 2 12); do
  add_cg_difference \
    "shincg7" \
    "${door_variants[1]}" \
    "${door_variants[$variant_number]}" \
    "$variant_number"
done
encode_webp "$door_source/门..png" "$cg_root/shincg7/shincg7-empty.webp"

echo "Chapter 2 assets imported into: $project_root"
