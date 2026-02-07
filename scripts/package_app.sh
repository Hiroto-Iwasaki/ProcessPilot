#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-ProcessPilot}"
BUNDLE_ID="${BUNDLE_ID:-com.local.processpilot}"
VERSION="${VERSION:-1.0.0}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"

if [[ -z "${GITHUB_OWNER}" || -z "${GITHUB_REPO}" ]]; then
  if REMOTE_URL="$(git -C "${PROJECT_ROOT}" remote get-url origin 2>/dev/null)"; then
    if [[ "${REMOTE_URL}" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      GITHUB_OWNER="${GITHUB_OWNER:-${BASH_REMATCH[1]}}"
      GITHUB_REPO="${GITHUB_REPO:-${BASH_REMATCH[2]}}"
    fi
  fi
fi

DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE_PATH="${PROJECT_ROOT}/.build/${BUILD_CONFIGURATION}/${APP_NAME}"

echo "Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "${BUILD_CONFIGURATION}" --product "${APP_NAME}"

echo "Creating app bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>PPGitHubOwner</key>
    <string>${GITHUB_OWNER}</string>
    <key>PPGitHubRepo</key>
    <string>${GITHUB_REPO}</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
    echo "Applying ad-hoc code signature..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "Done."
echo "App bundle: ${APP_BUNDLE}"
if [[ -n "${GITHUB_OWNER}" && -n "${GITHUB_REPO}" ]]; then
  echo "Update check source: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
else
  echo "Update check source is not configured."
  echo "Set GITHUB_OWNER and GITHUB_REPO when packaging."
fi
echo "You can launch it with:"
echo "  open \"${APP_BUNDLE}\""
