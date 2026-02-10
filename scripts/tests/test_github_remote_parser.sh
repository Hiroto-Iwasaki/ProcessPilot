#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/scripts/lib/github_remote_parser.sh"

assert_parse() {
  local input="$1"
  local expected_owner="$2"
  local expected_repo="$3"
  local output
  local owner
  local repo

  output="$(parse_github_owner_repo "${input}")"
  owner="${output%%$'\t'*}"
  repo="${output#*$'\t'}"

  if [[ "${owner}" != "${expected_owner}" || "${repo}" != "${expected_repo}" ]]; then
    echo "FAILED: parse_github_owner_repo '${input}' => '${owner}/${repo}' (expected '${expected_owner}/${expected_repo}')" >&2
    exit 1
  fi
}

assert_no_parse() {
  local input="$1"

  if parse_github_owner_repo "${input}" >/dev/null 2>&1; then
    echo "FAILED: parse_github_owner_repo '${input}' should not parse" >&2
    exit 1
  fi
}

assert_parse "https://github.com/octocat/ProcessPilot.git" "octocat" "ProcessPilot"
assert_parse "git@github.com:octocat/ProcessPilot.git" "octocat" "ProcessPilot"
assert_parse "https://github.com/octocat/repo.name.git" "octocat" "repo.name"
assert_parse "https://github.com/octocat/repo.name/" "octocat" "repo.name"
assert_parse "ssh://git@github.com/octocat/repo.name.git" "octocat" "repo.name"
assert_no_parse "https://example.com/octocat/repo.name.git"

echo "test_github_remote_parser.sh: all cases passed"
