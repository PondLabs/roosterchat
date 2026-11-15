#!/bin/sh
# Puts ONNX Runtime Web, the engine of face tracking in the browser
# (docs/adr/0006-face-tracking.md), next to its worker in web/face_tracking/,
# where `flutter build web` picks it up. Run from rooster/. Called by
# prepare-web.sh.
#
# A pinned version from the npm registry, checked against its hash: the
# app serves these files itself and loads nothing from a CDN. Only two files
# of the package are kept: the JavaScript with its wasm glue bundled in, and
# the wasm. The files are built, not written, and ignored by git.
set -eu
VERSION=1.31.1
SHA256=bdccdb9fbb9ab537247c0c734e9b1d2b1b338b4f2a09faa58f0dc1cfa27c312c
OUT=${OUT:-web/face_tracking}

if [ -f "$OUT/ort-wasm-simd-threaded.wasm" ] && [ -f "$OUT/ort.wasm.bundle.min.mjs" ]; then
  case "$(head -c 200 "$OUT/ort.wasm.bundle.min.mjs")" in
    *"ONNX Runtime Web v$VERSION"*) exit 0 ;;
  esac
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sSfL -o "$tmp/ort.tgz" "https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-$VERSION.tgz"
if [ "$(sha256sum "$tmp/ort.tgz" | cut -d' ' -f1)" != "$SHA256" ]; then
  echo "onnxruntime-web-$VERSION.tgz does not have the expected SHA-256" >&2
  exit 1
fi
tar -xzf "$tmp/ort.tgz" -C "$tmp" package/dist/ort.wasm.bundle.min.mjs package/dist/ort-wasm-simd-threaded.wasm
cp "$tmp/package/dist/ort.wasm.bundle.min.mjs" "$tmp/package/dist/ort-wasm-simd-threaded.wasm" "$OUT/"
