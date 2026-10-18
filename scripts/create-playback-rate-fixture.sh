#!/usr/bin/env bash
# Generated only in build/: no large binary is added to the repository.
set -euo pipefail
fixture_dir="${1:?Pass an output directory}"
mkdir -p "$fixture_dir"
timeout 180s ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=1920x1080:rate=24:duration=40' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=40' \
  -map 0:v -map 1:a -c:v libx264 -threads 2 -preset veryfast -crf 23 \
  -profile:v high -level:v 4.1 -pix_fmt yuv420p -g 48 \
  -c:a aac -b:a 128k -shortest -movflags +faststart \
  "$fixture_dir/synthetic-1080p24.mp4"
ffprobe -v error -show_format -show_streams -of json \
  "$fixture_dir/synthetic-1080p24.mp4" > "$fixture_dir/ffprobe.json"
python3 - "$fixture_dir/ffprobe.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
video = next(s for s in data["streams"] if s["codec_type"] == "video")
audio = next(s for s in data["streams"] if s["codec_type"] == "audio")
assert (video["codec_name"], video["width"], video["height"], video["pix_fmt"]) == (
    "h264", 1920, 1080, "yuv420p")
assert video["avg_frame_rate"] == "24/1"
assert audio["codec_name"] == "aac"
assert float(data["format"]["duration"]) >= 30
print("Verified synthetic 1080p24 H264 + AAC fixture")
PY
(cd "$fixture_dir" && sha256sum synthetic-1080p24.mp4 > SHA256SUMS)
