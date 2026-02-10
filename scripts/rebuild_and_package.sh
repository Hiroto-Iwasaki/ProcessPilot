#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKIP_TESTS="${SKIP_TESTS:-0}"
TEST_DESTINATION="${TEST_DESTINATION:-}"
GITHUB_REMOTE_PARSER_TEST_SCRIPT="${SCRIPT_DIR}/tests/test_github_remote_parser.sh"

cd "${PROJECT_ROOT}"

if [[ "${SKIP_TESTS}" != "1" ]]; then
  echo "Running shell regression tests..."
  bash "${GITHUB_REMOTE_PARSER_TEST_SCRIPT}"

  echo "Running test suite..."
  if [[ -n "${TEST_DESTINATION}" ]]; then
    swift test --destination "${TEST_DESTINATION}"
  else
    swift test
  fi
else
  echo "Skipping tests (SKIP_TESTS=1)."
fi

echo "Packaging app bundle..."
"${SCRIPT_DIR}/package_app.sh"
