# lib/cloudflare.sh — Cloudflare DNS helpers.
# shellcheck shell=bash

# Internal: call the Cloudflare API. Stdout: JSON body. Exit: non-zero on API error.
_sb_cf_api() {
  local method="$1" path="$2" body="${3:-}"
  : "${CF_API_TOKEN:?CF_API_TOKEN not set. Put it in .env or export it.}"
  : "${CF_ZONE_ID:?CF_ZONE_ID not set. Put it in .env or export it.}"

  local url="https://api.cloudflare.com/client/v4${path}"
  local response
  if [[ -n "$body" ]]; then
    response=$(curl -sS -X "$method" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body" \
      "$url")
  else
    response=$(curl -sS -X "$method" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      "$url")
  fi
  # Quick success sniff; actual parsing is up to callers.
  if ! printf '%s' "$response" | jq -e '.success' >/dev/null 2>&1; then
    local msg
    msg=$(printf '%s' "$response" | jq -r '.errors[0].message // "unknown Cloudflare API error"' 2>/dev/null || echo "unknown Cloudflare API error")
    sb_err "cloudflare: $msg"
    return 1
  fi
  printf '%s' "$response"
}

# Find an A record ID by FQDN. Prints the ID (or empty) and returns 0.
sb_cf_find_a_record() {
  local fqdn="$1"
  _sb_cf_api GET "/zones/$CF_ZONE_ID/dns_records?type=A&name=$fqdn" \
    | jq -r '.result[0].id // empty'
}

# Ensure an A record for fqdn points at ip. Creates if missing, updates if drifted.
sb_cf_upsert_a() {
  local fqdn="$1" ip="$2" proxied="${3:-false}"

  sb_require jq || return 1

  local existing
  existing=$(sb_cf_find_a_record "$fqdn")

  if [[ -z "$existing" ]]; then
    sb_info "creating A record: $fqdn -> $ip (proxied=$proxied)"
    if [[ "${SB_DRY_RUN:-0}" == "1" ]]; then return 0; fi
    _sb_cf_api POST "/zones/$CF_ZONE_ID/dns_records" \
      "$(jq -n --arg n "$fqdn" --arg ip "$ip" --argjson p "$proxied" \
          '{type:"A", name:$n, content:$ip, ttl:1, proxied:$p}')" >/dev/null
    sb_ok "DNS record created"
    return 0
  fi

  local current
  current=$(_sb_cf_api GET "/zones/$CF_ZONE_ID/dns_records/$existing" \
    | jq -r '.result.content')
  if [[ "$current" == "$ip" ]]; then
    sb_info "DNS already correct: $fqdn -> $ip"
    return 0
  fi

  sb_info "updating A record: $current -> $ip"
  if [[ "${SB_DRY_RUN:-0}" == "1" ]]; then return 0; fi
  _sb_cf_api PATCH "/zones/$CF_ZONE_ID/dns_records/$existing" \
    "$(jq -n --arg ip "$ip" '{content:$ip}')" >/dev/null
  sb_ok "DNS record updated"
}

# List A records for the current zone.
sb_cf_list_a() {
  _sb_cf_api GET "/zones/$CF_ZONE_ID/dns_records?type=A&per_page=100" \
    | jq -r '.result[] | "\(.name)\t\(.content)\t\(.proxied)"'
}

# `site-bootstrap dns <subcommand>` entrypoint.
sb_cmd_dns() {
  sb_load_env
  local sub="${1:-help}"
  shift || true

  case "$sub" in
    add|upsert)
      local fqdn="${1:?usage: dns add <fqdn> <ip> [--proxied]}"
      local ip="${2:?usage: dns add <fqdn> <ip> [--proxied]}"
      local proxied="false"
      [[ "${3:-}" == "--proxied" ]] && proxied="true"
      sb_cf_upsert_a "$fqdn" "$ip" "$proxied"
      ;;
    list|ls)
      printf '%-40s %-16s %s\n' NAME IP PROXIED
      sb_cf_list_a | awk -F '\t' '{printf "%-40s %-16s %s\n", $1, $2, $3}'
      ;;
    help|--help|"")
      cat <<'EOF'
site-bootstrap dns — Cloudflare DNS management.

Subcommands:
  add <fqdn> <ip> [--proxied]   Create or update an A record.
  list                          List all A records in the zone.

Needs CF_API_TOKEN and CF_ZONE_ID in env or .env.
EOF
      ;;
    *)
      sb_err "unknown dns subcommand: $sub"; return 2 ;;
  esac
}
