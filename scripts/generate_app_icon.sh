#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_ICNS="${1:-${PROJECT_ROOT}/assets/ProcessPilot.icns}"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="${TMP_DIR}/ProcessPilot.iconset"
BASE_PNG="${TMP_DIR}/base.png"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${ICONSET_DIR}"
mkdir -p "$(dirname "${OUTPUT_ICNS}")"

swift "${SCRIPT_DIR}/generate_app_icon.swift" "${BASE_PNG}"

create_icon() {
  local filename="$1"
  local size="$2"
  sips -z "${size}" "${size}" "${BASE_PNG}" --out "${ICONSET_DIR}/${filename}" >/dev/null
}

create_icon "icon_16x16.png" 16
create_icon "icon_16x16@2x.png" 32
create_icon "icon_32x32.png" 32
create_icon "icon_32x32@2x.png" 64
create_icon "icon_128x128.png" 128
create_icon "icon_128x128@2x.png" 256
create_icon "icon_256x256.png" 256
create_icon "icon_256x256@2x.png" 512
create_icon "icon_512x512.png" 512
create_icon "icon_512x512@2x.png" 1024

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
echo "Generated icns: ${OUTPUT_ICNS}"
