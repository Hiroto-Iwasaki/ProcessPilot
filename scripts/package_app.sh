#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REMOTE_PARSER_LIB="${SCRIPT_DIR}/lib/github_remote_parser.sh"

if [[ ! -f "${REMOTE_PARSER_LIB}" ]]; then
  echo "Error: missing GitHub remote parser at ${REMOTE_PARSER_LIB}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${REMOTE_PARSER_LIB}"

APP_NAME="${APP_NAME:-ProcessPilot}"
HELPER_PRODUCT_NAME="${HELPER_PRODUCT_NAME:-ProcessPilotPrivilegedHelper}"
BUNDLE_ID="${BUNDLE_ID:-com.local.processpilot}"
VERSION="${VERSION:-1.0.0}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
GITHUB_OWNER="${GITHUB_OWNER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
ICON_FILE="${ICON_FILE:-ProcessPilot.icns}"

CONTRACT_FILE="${PROJECT_ROOT}/ProcessPilotCommon/PrivilegedHelperContract.swift"
PRIVILEGED_HELPER_LABEL="$(sed -n 's/.*defaultMachServiceName = \"\([^\"]*\)\".*/\1/p' "${CONTRACT_FILE}" | head -n 1)"
PRIVILEGED_HELPER_DAEMON_PLIST="$(sed -n 's/.*defaultDaemonPlistName = \"\([^\"]*\)\".*/\1/p' "${CONTRACT_FILE}" | head -n 1)"

if [[ -z "${PRIVILEGED_HELPER_LABEL}" ]]; then
  echo "Error: failed to read privileged helper label from ${CONTRACT_FILE}" >&2
  exit 1
fi

if [[ -z "${PRIVILEGED_HELPER_DAEMON_PLIST}" ]]; then
  echo "Error: failed to read privileged helper daemon plist name from ${CONTRACT_FILE}" >&2
  exit 1
fi

if [[ -z "${GITHUB_OWNER}" || -z "${GITHUB_REPO}" ]]; then
  if REMOTE_URL="$(git -C "${PROJECT_ROOT}" remote get-url origin 2>/dev/null)"; then
    if PARSED_GITHUB_REMOTE="$(parse_github_owner_repo "${REMOTE_URL}")"; then
      PARSED_GITHUB_OWNER="${PARSED_GITHUB_REMOTE%%$'\t'*}"
      PARSED_GITHUB_REPO="${PARSED_GITHUB_REMOTE#*$'\t'}"
      GITHUB_OWNER="${GITHUB_OWNER:-${PARSED_GITHUB_OWNER}}"
      GITHUB_REPO="${GITHUB_REPO:-${PARSED_GITHUB_REPO}}"
    fi
  fi
fi

DIST_DIR="${PROJECT_ROOT}/dist"
GENERATED_DIR="${DIST_DIR}/.generated"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
HELPER_TOOLS_DIR="${CONTENTS_DIR}/Library/HelperTools"
LAUNCH_DAEMONS_DIR="${CONTENTS_DIR}/Library/LaunchDaemons"
EXECUTABLE_PATH="${PROJECT_ROOT}/.build/${BUILD_CONFIGURATION}/${APP_NAME}"
HELPER_EXECUTABLE_PATH="${PROJECT_ROOT}/.build/${BUILD_CONFIGURATION}/${HELPER_PRODUCT_NAME}"
HELPER_DESTINATION_PATH="${HELPER_TOOLS_DIR}/${PRIVILEGED_HELPER_LABEL}"
HELPER_BUNDLE_PROGRAM="Contents/Library/HelperTools/${PRIVILEGED_HELPER_LABEL}"
HELPER_DAEMON_PLIST_DESTINATION_PATH="${LAUNCH_DAEMONS_DIR}/${PRIVILEGED_HELPER_DAEMON_PLIST}"
ICON_SOURCE_PATH="${PROJECT_ROOT}/assets/${ICON_FILE}"
ICON_SCRIPT_PATH="${PROJECT_ROOT}/scripts/generate_app_icon.sh"
HELPER_LAUNCHD_TEMPLATE="${PROJECT_ROOT}/PrivilegedHelper/Launchd.plist.template"
HELPER_LAUNCHD_PLIST="${GENERATED_DIR}/${PRIVILEGED_HELPER_DAEMON_PLIST}"

escape_for_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_helper_template() {
  local template_path="$1"
  local output_path="$2"
  local escaped_label
  local escaped_bundle_program

  escaped_label="$(escape_for_sed "${PRIVILEGED_HELPER_LABEL}")"
  escaped_bundle_program="$(escape_for_sed "${HELPER_BUNDLE_PROGRAM}")"

  sed \
    -e "s/@HELPER_LABEL@/${escaped_label}/g" \
    -e "s/@HELPER_BUNDLE_PROGRAM@/${escaped_bundle_program}/g" \
    "${template_path}" > "${output_path}"
}

if [[ ! -f "${HELPER_LAUNCHD_TEMPLATE}" ]]; then
  echo "Error: helper launchd template file is missing." >&2
  exit 1
fi

mkdir -p "${GENERATED_DIR}"
render_helper_template "${HELPER_LAUNCHD_TEMPLATE}" "${HELPER_LAUNCHD_PLIST}"

if [[ ! -f "${ICON_SOURCE_PATH}" && -x "${ICON_SCRIPT_PATH}" ]]; then
  echo "Generating app icon..."
  "${ICON_SCRIPT_PATH}" "${ICON_SOURCE_PATH}"
fi

ICON_PLIST_ENTRY=""
if [[ -f "${ICON_SOURCE_PATH}" ]]; then
  ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>'"${ICON_FILE}"$'</string>'
fi

echo "Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "${BUILD_CONFIGURATION}" --product "${APP_NAME}"
echo "Building ${HELPER_PRODUCT_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "${BUILD_CONFIGURATION}" --product "${HELPER_PRODUCT_NAME}"

echo "Creating app bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
mkdir -p "${HELPER_TOOLS_DIR}" "${LAUNCH_DAEMONS_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${HELPER_EXECUTABLE_PATH}" ]]; then
  cp "${HELPER_EXECUTABLE_PATH}" "${HELPER_DESTINATION_PATH}"
  chmod +x "${HELPER_DESTINATION_PATH}"
fi

cp "${HELPER_LAUNCHD_PLIST}" "${HELPER_DAEMON_PLIST_DESTINATION_PATH}"

if [[ -f "${ICON_SOURCE_PATH}" ]]; then
  cp "${ICON_SOURCE_PATH}" "${RESOURCES_DIR}/${ICON_FILE}"
fi

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
${ICON_PLIST_ENTRY}
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>PPPrivilegedHelperLabel</key>
    <string>${PRIVILEGED_HELPER_LABEL}</string>
    <key>PPPrivilegedHelperDaemonPlist</key>
    <string>${PRIVILEGED_HELPER_DAEMON_PLIST}</string>
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
echo "Privileged helper executable: ${HELPER_DESTINATION_PATH}"
echo "Privileged helper daemon plist: ${HELPER_DAEMON_PLIST_DESTINATION_PATH}"
if [[ -n "${GITHUB_OWNER}" && -n "${GITHUB_REPO}" ]]; then
  echo "Update check source: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
else
  echo "Update check source is not configured."
  echo "Set GITHUB_OWNER and GITHUB_REPO when packaging."
fi
echo "You can launch it with:"
echo "  open \"${APP_BUNDLE}\""
