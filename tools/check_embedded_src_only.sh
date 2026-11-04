#!/usr/bin/env bash
# Type-check the embedded frontend from a copy of src/ alone, as an embedder
# that vendors it would compile it. Run from the repository root after
# `nimble setup`.
set -euo pipefail

layout=$(mktemp -d)
trap 'rm -rf "$layout"' EXIT

mkdir "$layout/tools"
cp -r src config.nims nimble.paths "$layout/"
cp tools/embedded_smoke.nim "$layout/tools/"

(
  cd "$layout"
  nim check --hints:off -d:moe.embedded tools/embedded_smoke.nim
)
