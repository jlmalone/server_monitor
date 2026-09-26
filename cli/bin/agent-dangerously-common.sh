#!/usr/bin/env bash
# Shared helpers for agent dangerously wrappers.
set -euo pipefail

agent_dangerously_script_dir() {
  local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="${dir}/${source}"
  done
  cd "$(dirname "$source")" && pwd
}

agent_dangerously_config_dir() {
  printf '%s\n' "${HOME}/.config/agent-dangerously"
}

agent_dangerously_manifest() {
  printf '%s\n' "$(agent_dangerously_config_dir)/manifest.env"
}

agent_dangerously_load_manifest() {
  local manifest
  manifest="$(agent_dangerously_manifest)"
  if [[ -f "$manifest" ]]; then
    # shellcheck disable=SC1090
    source "$manifest"
  fi
}

agent_dangerously_resolve_real() {
  local name="$1"
  local fallback="$2"
  local bin_dir="${HOME}/.local/bin"
  local candidate="${bin_dir}/${name}.real"

  agent_dangerously_load_manifest
  local from_manifest="${!name:-}"
  if [[ -n "$from_manifest" && -x "$from_manifest" ]]; then
    printf '%s\n' "$from_manifest"
    return 0
  fi
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if [[ -n "$fallback" && -x "$fallback" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  printf 'agent dangerously wrapper: could not resolve real binary for %s\n' "$name" >&2
  return 1
}
