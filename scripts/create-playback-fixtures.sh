#!/usr/bin/env bash
# Synthetic, redistributable media used only by the Android integration runner.
set -euo pipefail
fixture_dir="${1:?Pass an output directory}"
mkdir -p "$fixture_dir"

ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i 'testsrc2=size=180x320:rate=24:duration=3' \
  -f lavfi -i 'sine=frequency=440:duration=3' \
  -f lavfi -i 'sine=frequency=880:duration=3' \
  -map 0:v -map 1:a -map 2:a -c:v libx264 -threads 2 -preset ultrafast \
  -pix_fmt yuv420p -c:a aac -metadata:s:a:0 language=eng \
  -metadata:s:a:1 language=zho -movflags +faststart "$fixture_dir/portrait.mp4"
ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i 'testsrc2=size=320x180:rate=24:duration=3' \
  -c:v libx264 -threads 2 -preset ultrafast -pix_fmt yuv420p \
  "$fixture_dir/landscape.mp4"
ffmpeg -hide_banner -loglevel error -y -display_rotation 90 \
  -i "$fixture_dir/landscape.mp4" -c copy "$fixture_dir/rotated.mp4"
ffmpeg -hide_banner -loglevel error -y -display_rotation 270 \
  -i "$fixture_dir/landscape.mp4" -c copy "$fixture_dir/rotated270.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$fixture_dir/landscape.mp4" \
  -vf setsar=2/1 -c:v libx264 -threads 2 -preset ultrafast "$fixture_dir/sar.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$fixture_dir/portrait.mp4" \
  -map 0:v -map 0:a:0 -c:v libvpx-vp9 -threads 2 -deadline realtime \
  -cpu-used 8 -c:a libopus "$fixture_dir/portrait.webm"

ffmpeg -hide_banner -loglevel error -y -i "$fixture_dir/portrait.mp4" \
  -map 0:v -map 0:a:0 -c:v libx265 -threads 2 -preset ultrafast \
  -x265-params 'pools=1:frame-threads=1:log-level=error' \
  -c:a eac3 "$fixture_dir/hevc.mkv"
ffmpeg -hide_banner -loglevel error -y -i "$fixture_dir/portrait.mp4" \
  -map 0:v -map 0:a:0 -c:v libaom-av1 -threads 2 -cpu-used 8 \
  -crf 40 -c:a libopus "$fixture_dir/av1.mkv"

cat > "$fixture_dir/chinese.ass" <<'SUBTITLE'
[Script Info]
ScriptType: v4.00+
PlayResX: 180
PlayResY: 320
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Noto Sans CJK SC,16,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,5,5,20,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:03.00,Default,,0,0,0,,Privi 中文字幕測試
SUBTITLE
ffmpeg -hide_banner -loglevel error -y -i "$fixture_dir/portrait.mp4" \
  -i "$fixture_dir/chinese.ass" -map 0:v -map 0:a -map 1:s \
  -c:v copy -c:a ac3 -c:s ass "$fixture_dir/tracks.mkv"
