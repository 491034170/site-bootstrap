# lib/deploy.sh — deploy and rollback logic.
# shellcheck shell=bash

# Read one config value with a default fallback.
_sb_cfg() {
  local key="$1" default="${2:-}"
  local val
  val="$(sb_yaml_get "$SB_CONFIG" "$key" || true)"
  if [[ -z "$val" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

# Produce the remote path for a given domain.
_sb_remote_path() {
  printf '/var/www/%s' "$1"
}

sb_cmd_deploy() {
  sb_require_config || return 1
  sb_load_env

  local name domain server type source build port proxied ssl_provider ssl_email nginx_custom nginx_template
  name="$(_sb_cfg name)"
  domain="$(_sb_cfg domain)"
  server="$(_sb_cfg server)"
  type="$(_sb_cfg deploy.type static)"
  source="$(_sb_cfg deploy.source .)"
  build="$(_sb_cfg deploy.build)"
  port="$(_sb_cfg deploy.port 3000)"
  proxied="$(_sb_cfg dns.proxied false)"
  ssl_provider="$(_sb_cfg ssl.provider letsencrypt)"
  ssl_email="$(_sb_cfg ssl.email)"
  nginx_custom="$(_sb_cfg nginx.custom)"
  nginx_template="$(_sb_cfg nginx.template)"

  if [[ -z "$name" || -z "$domain" || -z "$server" ]]; then
    sb_err "site.yaml is missing required fields: name, domain, server"
    return 1
  fi

  # Validate deploy.source *before* any network or remote action — fail fast
  # on obvious config mistakes instead of wasting an SSH connection first.
  # The '.' case is legitimate (user explicitly deploys the project root).
  if [[ "$type" == "static" && ! -d "$source" && "$source" != "." ]]; then
    sb_err "deploy.source does not exist: $source"
    if [[ -n "$build" ]]; then
      sb_info "you set deploy.build to '$build' but the output dir '$source' is missing."
      sb_info "the build may have failed silently; re-run with --verbose."
    else
      sb_info "did you forget a deploy.build step? or set deploy.source to '.'?"
    fi
    return 1
  fi

  sb_step "Deploying $name"
  sb_info "domain:  $domain"
  sb_info "server:  $server"
  sb_info "type:    $type"

  sb_require ssh  || return 1
  sb_require rsync || return 1

  local server_ip
  server_ip="$(sb_ssh_host "$server" || true)"
  if [[ -z "$server_ip" ]]; then
    sb_warn "could not resolve '$server' via ssh -G. Make sure it's in ~/.ssh/config."
  else
    sb_info "ip:      $server_ip"
  fi

  # Step 1: Cloudflare DNS (if credentials present).
  if [[ -n "${CF_API_TOKEN:-}" && -n "${CF_ZONE_ID:-}" && -n "$server_ip" ]]; then
    sb_step "DNS via Cloudflare"
    sb_cf_upsert_a "$domain" "$server_ip" "$proxied"
    sb_info "waiting 5s for propagation..."
    sb_run sleep 5
  else
    sb_warn "skipping DNS (no CF_API_TOKEN / CF_ZONE_ID, or ssh -G failed)"
  fi

  # Step 2: Build (if build command specified).
  if [[ -n "$build" && "$build" != "null" ]]; then
    sb_step "Build"
    sb_info "\$ $build"
    sb_run bash -c "$build"
  fi

  # Step 3: Upload via rsync.
  sb_step "Upload"
  local remote_path
  remote_path="$(_sb_remote_path "$domain")"

  # Snapshot previous deployment for rollback.
  sb_run ssh "$server" "mkdir -p $remote_path && if [[ -d '$remote_path' && ! -z \"\$(ls -A $remote_path 2>/dev/null)\" ]]; then rsync -a --delete '$remote_path/' '$remote_path.prev/'; fi"

  local src_dir
  if [[ "$type" == "static" ]]; then
    # Already validated existence above — use as-is, except the '.' sentinel
    # still needs to map to the project root (which is cwd).
    src_dir="$source"
    if [[ "$src_dir" == "." && ! -d "." ]]; then
      # Almost impossible (cwd must exist) but keep the guard for clarity.
      sb_err "project root does not exist"
      return 1
    fi
  else
    src_dir="."
  fi

  local rsync_flags=(-az --delete)
  [[ "${SB_VERBOSE:-0}" == "1" ]] && rsync_flags+=(-v)
  local rsync_excludes=(
    --exclude=.git
    --exclude=node_modules
    --exclude=.env
    --exclude=.env.local
    --exclude='._*'
    --exclude='.!*'
    --exclude=.DS_Store
    --exclude=site.yaml
  )

  sb_run rsync "${rsync_flags[@]}" "${rsync_excludes[@]}" "$src_dir/" "$server:$remote_path/"
  sb_run ssh "$server" "find $remote_path -type f -exec chmod 644 {} + ; find $remote_path -type d -exec chmod 755 {} +"

  if [[ "$type" == "node" ]]; then
    sb_step "Install remote deps + pm2"
    sb_run ssh "$server" "cd $remote_path && npm install --production --silent"
    sb_run ssh "$server" "cd $remote_path && (pm2 describe $name > /dev/null 2>&1 && pm2 restart $name || pm2 start npm --name $name -- start)"
  fi

  # Step 4: Nginx config.
  sb_step "Nginx"
  local tpl_path
  if [[ -n "$nginx_custom" ]]; then
    tpl_path="$nginx_custom"
  elif [[ -n "$nginx_template" ]]; then
    tpl_path="$SB_TEMPLATES/nginx/${nginx_template}.conf.tpl"
  else
    case "$type" in
      static) tpl_path="$SB_TEMPLATES/nginx/static.conf.tpl" ;;
      node)   tpl_path="$SB_TEMPLATES/nginx/proxy.conf.tpl" ;;
    esac
  fi

  if [[ ! -f "$tpl_path" ]]; then
    sb_err "nginx template not found: $tpl_path"
    return 1
  fi

  local tmp_conf="${TMPDIR:-/tmp}/site-bootstrap-$$.conf"
  sb_render_template "$tpl_path" "$tmp_conf" \
    domain "$domain" \
    port "$port" \
    root "$remote_path"

  sb_run scp -q "$tmp_conf" "$server:/etc/nginx/sites-enabled/${domain}.conf"
  rm -f "$tmp_conf"

  sb_run ssh "$server" "nginx -t"
  sb_run ssh "$server" "systemctl reload nginx"
  sb_ok "nginx reloaded"

  # Step 5: SSL.
  if [[ "$ssl_provider" == "letsencrypt" ]]; then
    sb_step "SSL"
    local has_cert
    has_cert=$(ssh "$server" "test -d /etc/letsencrypt/live/$domain && echo yes || echo no" 2>/dev/null || echo no)
    if [[ "$has_cert" == "no" ]]; then
      local email_flag="--register-unsafely-without-email"
      [[ -n "$ssl_email" ]] && email_flag="--email $ssl_email"
      if sb_run ssh "$server" "certbot --nginx -d $domain --non-interactive --agree-tos $email_flag"; then
        sb_ok "certificate issued"
      else
        sb_warn "certbot failed — DNS may not have propagated. Re-run 'site-bootstrap cert $domain' later."
      fi
    else
      sb_info "certificate already present"
    fi
  fi

  # Step 6: Verify.
  sb_step "Verify"
  local proto="https"
  [[ "$ssl_provider" == "none" ]] && proto="http"
  local status
  status=$(ssh "$server" "curl -sI ${proto}://${domain} 2>/dev/null | head -1 || echo 'unreachable'")
  sb_info "$status"

  sb_ok "deployed: ${proto}://${domain}"
}

sb_cmd_rollback() {
  sb_require_config || return 1
  local domain server remote_path
  domain="$(_sb_cfg domain)"
  server="$(_sb_cfg server)"
  remote_path="$(_sb_remote_path "$domain")"

  sb_step "Rollback $domain"
  sb_info "server:  $server"
  sb_info "path:    $remote_path -> $remote_path.prev"

  local has_prev
  has_prev=$(ssh "$server" "test -d ${remote_path}.prev && echo yes || echo no" 2>/dev/null || echo no)
  if [[ "$has_prev" != "yes" ]]; then
    sb_err "no previous deployment snapshot at ${remote_path}.prev"
    return 1
  fi

  sb_confirm "Roll back $domain to previous snapshot?" || { sb_info "aborted"; return 0; }

  # Swap current and prev, keeping the previous current as a safety backup.
  sb_run ssh "$server" "rsync -a --delete '${remote_path}.prev/' '${remote_path}/' && rm -rf '${remote_path}.prev'"
  sb_run ssh "$server" "systemctl reload nginx"
  sb_ok "rolled back"
}
