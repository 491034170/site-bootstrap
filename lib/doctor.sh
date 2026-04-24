# lib/doctor.sh — environment sanity check.
# shellcheck shell=bash

sb_cmd_doctor() {
  sb_load_env
  sb_step "Local tools"
  local ok=1
  for bin in bash ssh rsync curl jq awk sed; do
    if command -v "$bin" >/dev/null 2>&1; then
      sb_ok "$bin: $(command -v "$bin")"
    else
      sb_err "$bin: not found"
      ok=0
    fi
  done

  sb_step "Config"
  if [[ -f "$SB_CONFIG" ]]; then
    sb_ok "$SB_CONFIG found"
    for k in name domain server; do
      local v; v="$(sb_yaml_get "$SB_CONFIG" "$k" || true)"
      if [[ -n "$v" ]]; then
        sb_ok "  $k: $v"
      else
        sb_err "  $k: missing"
        ok=0
      fi
    done
  else
    sb_warn "$SB_CONFIG not found (run 'site-bootstrap new <name>' to scaffold)"
  fi

  sb_step "Cloudflare credentials"
  if [[ -n "${CF_API_TOKEN:-}" ]]; then sb_ok "CF_API_TOKEN set"; else sb_warn "CF_API_TOKEN missing (DNS automation disabled)"; fi
  if [[ -n "${CF_ZONE_ID:-}" ]];  then sb_ok "CF_ZONE_ID set";  else sb_warn "CF_ZONE_ID missing (DNS automation disabled)"; fi

  if [[ -f "$SB_CONFIG" ]]; then
    local server; server="$(sb_yaml_get "$SB_CONFIG" server || true)"
    if [[ -n "$server" ]]; then
      sb_step "Remote connectivity ($server)"
      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" 'echo ok' >/dev/null 2>&1; then
        sb_ok "SSH reachable"
        if ssh "$server" 'command -v nginx' >/dev/null 2>&1; then sb_ok "nginx present"; else sb_warn "nginx not found on server"; fi
        if ssh "$server" 'command -v certbot' >/dev/null 2>&1; then sb_ok "certbot present"; else sb_warn "certbot not found on server"; fi
      else
        sb_err "SSH to '$server' failed"; ok=0
      fi
    fi
  fi

  [[ $ok -eq 1 ]]
}
