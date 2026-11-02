#!/bin/sh -e
# Builds the voice DSP (rust/audio_dsp) to WebAssembly for the AudioWorklet
# and puts it in web/, where `flutter build web` picks it up. Run from
# rooster/. Called by prepare-web.sh and by CI.
#
# Needs `rustup target add wasm32-unknown-unknown`. If cargo is not on PATH
# but docker is, the build runs in the official rust image.
# Stripped: the symbol names were a 3.4 MB section of a file every first
# call on the web downloads (11 MB gzipped), and nothing reads them from a
# wasm module at runtime. Only this build: the desktop libraries keep their
# symbols for crash reports.
if command -v cargo >/dev/null 2>&1; then
  (cd .. && CARGO_PROFILE_RELEASE_STRIP=true cargo build -p audio_dsp --release --target wasm32-unknown-unknown)
else
  docker run --rm -v "$(readlink -f ..)":/w -w /w -e CARGO_PROFILE_RELEASE_STRIP=true rust:1 \
    sh -c 'rustup target add wasm32-unknown-unknown >/dev/null && cargo build -p audio_dsp --release --target wasm32-unknown-unknown && chown -R '"$(id -u):$(id -g)"' /w/target'
fi
cp ../target/wasm32-unknown-unknown/release/audio_dsp.wasm ./web/audio_dsp.wasm
