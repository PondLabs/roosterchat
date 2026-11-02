#!/bin/sh -e
# The demo video's media that isn't a capture, made into $DEMO_WORK
# (default /tmp/rooster-demo):
#
# - kitten.y4m: Lou's camera for screens/capture-video.mjs, and kitten.webm,
#   the same clip, played over his tile in the video. "Burmese Kitten
#   Grooming Itself" by Alistair Findlay, CC0, Wikimedia Commons.
# - noisy_48k.wav: someone talking over a mechanical keyboard, the
#   microphone Maya's settings meter hears in capture-video.mjs. The voice
#   and the typing are rust/audio_dsp's own test fixtures (CMU ARCTIC and a
#   CC0 recording, see its testdata/README.md).
# - clean_48k.wav: that recording through the voice DSP with the shipping
#   settings (rust/audio_dsp's process_wav example), what the room hears.
#
# Needs ffmpeg, curl and Docker (for cargo; a local Rust works too, with
# CARGO=cargo).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
WORK=${DEMO_WORK:-/tmp/rooster-demo}
mkdir -p "$WORK"
cd "$WORK"

if [ ! -f kitten.webm ]; then
  curl -sSfL -A "rooster-demo" -o kitten-source.webm \
    "https://upload.wikimedia.org/wikipedia/commons/e/ed/Burmese_Kitten_Grooming_Itself.webm"
  ffmpeg -loglevel error -y -ss 2 -t 12 -i kitten-source.webm -vf "scale=960:540,fps=30" -pix_fmt yuv420p kitten.y4m
  ffmpeg -loglevel error -y -ss 2 -t 12 -i kitten-source.webm -vf "scale=960:540,fps=30" -an -c:v libvpx-vp9 -b:v 2M kitten.webm
fi

D="$ROOT/rust/audio_dsp/testdata"
# 1 s of typing alone, then the voice over the typing.
ffmpeg -loglevel error -y -i "$D/local_speech_16k.wav" -stream_loop -1 -i "$D/background_keyboard_mechanical_16k.wav" \
  -filter_complex "[0]adelay=1000,apad=pad_dur=1[v];[1]volume=0.7[n];[v][n]amix=inputs=2:duration=first:normalize=0,aresample=48000" \
  -ac 1 -c:a pcm_s16le noisy_48k.wav
if [ -n "$CARGO" ]; then
  (cd "$ROOT" && $CARGO run -q -p audio_dsp --release --example process_wav -- "$WORK/noisy_48k.wav" "$WORK/clean_48k.wav")
else
  mkdir -p target
  docker run --rm -v "$ROOT":/w -v "$WORK":/out -e CARGO_TARGET_DIR=/out/target -w /w rust:1 sh -c \
    "cargo run -q -p audio_dsp --release --example process_wav -- /out/noisy_48k.wav /out/clean_48k.wav && chown -R $(id -u):$(id -g) /out"
fi
ls -la "$WORK"
