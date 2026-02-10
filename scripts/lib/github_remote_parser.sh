#!/usr/bin/env bash

parse_github_owner_repo() {
  local remote_url="$1"
  local normalized_remote_url

  normalized_remote_url="${remote_url%/}"
  normalized_remote_url="${normalized_remote_url%.git}"

  if [[ "${normalized_remote_url}" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}
