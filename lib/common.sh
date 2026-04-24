# lib/common.sh — shared helpers for site-bootstrap.
# shellcheck shell=bash

# Color output helpers. Disable automatically when not a TTY or NO_COLOR is set.
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  SB_C_RESET=$'\033[0m'
  SB_C_BOLD=$'\033[1m'
  SB_C_DIM=$'\033[2m'
  SB_C_RED=$'\033[31m'
  SB_C_GREEN=$'\033[32m'
  SB_C_YELLOW=$'\033[33m'
  SB_C_BLUE=$'\033[34m'
  SB_C_CYAN=$'\033[36m'
else
  SB_C_RESET="" SB_C_BOLD="" SB_C_DIM="" SB_C_RED="" SB_C_GREEN="" SB_C_YELLOW="" SB_C_BLUE="" SB_C_CYAN=""
fi

sb_step() { printf '%s==>%s %s\n' "$SB_C_CYAN$SB_C_BOLD" "$SB_C_RESET" "$*" >&2; }
sb_info() { printf '    %s\n' "$*" >&2; }
sb_warn() { printf '%swarn:%s %s\n' "$SB_C_YELLOW" "$SB_C_RESET" "$*" >&2; }
sb_err()  { printf '%serror:%s %s\n' "$SB_C_RED" "$SB_C_RESET" "$*" >&2; }
sb_ok()   { printf '%s✓%s %s\n' "$SB_C_GREEN" "$SB_C_RESET" "$*" >&2; }
sb_debug() { [[ "${SB_VERBOSE:-0}" == "1" ]] && printf '%s[debug] %s%s\n' "$SB_C_DIM" "$*" "$SB_C_RESET" >&2 || true; }

# Run a command, or print it under --dry-run.
sb_run() {
  if [[ "${SB_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$SB_C_DIM" "$SB_C_RESET" "$*" >&2
    return 0
  fi
  sb_debug "+ $*"
  "$@"
}

# Required binary check.
sb_require() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    sb_err "required tool not found: $bin"
    return 1
  fi
}

# Load .env from current dir if present. Uses `set -a` so vars are exported.
sb_load_env() {
  local env_file="${1:-.env}"
  if [[ -f "$env_file" ]]; then
    sb_debug "loading env from $env_file"
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

# Minimal YAML reader: extract top-level scalar values and one level of nested
# scalars. Works for our flat-ish site.yaml schema. Keeps zero-dependency.
#
# Usage: sb_yaml_get <file> <key>
#   - dotted keys allowed: sb_yaml_get site.yaml deploy.type
sb_yaml_get() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { split(key, parts, "."); depth = length(parts); level = 0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      # count leading spaces (assume 2-space indentation)
      match($0, /^[[:space:]]*/)
      indent = RLENGTH
      cur_level = int(indent / 2) + 1
      # strip leading/trailing whitespace
      line = $0
      sub(/^[[:space:]]+/, "", line)
      # key:[ value]
      if (match(line, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
        key_here = substr(line, 1, RLENGTH - 1)
        val = substr(line, RLENGTH + 1)
        sub(/^[[:space:]]+/, "", val)
        # unwrap quotes
        if (val ~ /^".*"$/) val = substr(val, 2, length(val) - 2)
        if (val ~ /^'\''.*'\''$/) val = substr(val, 2, length(val) - 2)
        stack[cur_level] = key_here
        if (cur_level == depth) {
          match_ok = 1
          for (i = 1; i <= depth; i++) if (stack[i] != parts[i]) match_ok = 0
          if (match_ok && val != "") { print val; exit 0 }
        }
      }
    }
  ' "$file"
}

# Resolve an SSH alias to its hostname (IP) via `ssh -G`.
sb_ssh_host() {
  local alias="$1"
  ssh -G "$alias" 2>/dev/null | awk '/^hostname / {print $2}'
}

# Check a site.yaml exists and is readable.
sb_require_config() {
  if [[ ! -f "$SB_CONFIG" ]]; then
    sb_err "config not found: $SB_CONFIG"
    sb_info "run '$(basename "$0") new <name>' to scaffold one, or pass --config <path>"
    return 1
  fi
}

# Portable in-place template substitution (ExFAT-safe; avoids sed -i quirks).
sb_render_template() {
  local tpl="$1" out="$2"
  shift 2
  local content
  content="$(cat "$tpl")"
  while [[ $# -ge 2 ]]; do
    local key="$1" val="$2"; shift 2
    # escape slashes and ampersands in replacement
    local esc
    esc="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
    content="$(printf '%s' "$content" | sed "s|{{${key}}}|${esc}|g")"
  done
  printf '%s\n' "$content" > "$out"
}

# Confirm (y/N). Returns 0 if user says yes, 1 otherwise. Skipped under --dry-run.
sb_confirm() {
  local prompt="${1:-Continue?}"
  if [[ "${SB_DRY_RUN:-0}" == "1" ]]; then return 0; fi
  if [[ "${SB_ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}
