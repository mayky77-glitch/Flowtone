#!/usr/bin/env bash
set -euo pipefail

default_executable="$HOME/Library/Application Support/Flowtone/stable-audio-mlx"
executable="${FLOWTONE_STABLE_AUDIO_EXECUTABLE:-$default_executable}"
output="${TMPDIR:-/tmp}/flowtone-stable-audio-benchmark.wav"
prompt="instrumental ambient electronic music, warm evolving pads, gentle pulse, no vocals"
negative_prompt="vocals, singing, speech, lyrics, words"
seconds=30
seed=424242

usage() {
  cat <<'USAGE'
Usage: scripts/benchmark-stable-audio.sh [--executable PATH] [--output WAV]

Runs one fixed Stable Audio 3 Small-Music MLX benchmark. No model is installed
or downloaded. Override the executable with FLOWTONE_STABLE_AUDIO_EXECUTABLE.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --executable)
      [[ $# -ge 2 ]] || { echo "--executable requires a path" >&2; exit 64; }
      executable="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a WAV path" >&2; exit 64; }
      output="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ ! -f "$executable" || ! -x "$executable" ]]; then
  echo "Stable Audio executable is missing or not executable: $executable" >&2
  echo "Install official MLX runtime manually, then copy or symlink its sa3 wrapper to: $default_executable" >&2
  exit 69
fi

if [[ -e "$output" ]]; then
  echo "Refusing to overwrite existing benchmark output: $output" >&2
  exit 73
fi

mkdir -p "$(dirname "$output")"
start_seconds="$(date +%s)"
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$executable" \
  --prompt "$prompt" \
  --negative-prompt "$negative_prompt" \
  --dit sm-music \
  --decoder same-s \
  --seconds "$seconds" \
  --steps 8 \
  --seed "$seed" \
  --out "$output"
end_seconds="$(date +%s)"

if [[ ! -s "$output" ]]; then
  echo "Stable Audio produced no WAV output: $output" >&2
  exit 74
fi

if [[ "$(LC_ALL=C dd if="$output" bs=1 count=4 2>/dev/null)" != "RIFF" || \
  "$(LC_ALL=C dd if="$output" bs=1 skip=8 count=4 2>/dev/null)" != "WAVE" ]]; then
  echo "Stable Audio output is not a WAV file: $output" >&2
  exit 74
fi

bytes="$(wc -c < "$output" | tr -d '[:space:]')"
wall_seconds=$((end_seconds - start_seconds))
printf 'stable_audio_benchmark status=passed seconds=%s seed=%s wall_seconds=%s bytes=%s output=%q\n' \
  "$seconds" "$seed" "$wall_seconds" "$bytes" "$output"
