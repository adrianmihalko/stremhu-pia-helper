#!/usr/bin/env bash
set -euo pipefail

BASE_URL=""
token_env=""
base_env=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_PATH=".env"
if [[ ! -f "$ENV_PATH" && -f "${SCRIPT_DIR}/.env" ]]; then
  ENV_PATH="${SCRIPT_DIR}/.env"
fi
if [[ ! -f "$ENV_PATH" && -f "/.env" ]]; then
  ENV_PATH="/.env"
fi
if [[ -f "$ENV_PATH" ]]; then
  token_env="$(grep -E '^TOKEN=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  base_env="$(grep -E '^BASE_URL=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
fi
# Fallback to environment variables if provided
if [[ -z "$token_env" && -n "${TOKEN-}" ]]; then
  token_env="$TOKEN"
fi
if [[ -z "$base_env" && -n "${BASE_URL-}" ]]; then
  base_env="$BASE_URL"
fi

TOOL_NAME="StremHU PIA Helper by madrian"
TOOL_VERSION="0.1"
UPDATE_URL="https://raw.githubusercontent.com/adrianmihalko/stremhu-pia-helper/refs/heads/main/pia-helper.sh"

maybe_update() {
  local tmp_file
  tmp_file="$(mktemp)"
  echo "Frissítés... letöltés: ${UPDATE_URL}"
  if curl --fail --silent --show-error --location "${UPDATE_URL}" -o "$tmp_file"; then
    if mv "$tmp_file" "$(readlink -f "$0")"; then
      chmod +x "$(readlink -f "$0")" || true
      echo "Sikeres frissítés. Indítsd újra a scriptet."
      exit 0
    else
      echo "Frissítés sikertelen (nem tudtam felülírni a scriptet)." >&2
      exit 1
    fi
  else
    echo "Frissítés sikertelen (curl hiba)." >&2
    exit 1
  fi
}

run_setup() {
  local ENV_FILE="$ENV_PATH"
  local TIMESTAMP
  TIMESTAMP="$(date +%Y%m%d%H%M%S)"

  print_section() {
    echo
    echo "== $1 =="
  }

  echo "${TOOL_NAME} v${TOOL_VERSION}"

  if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" "${ENV_FILE}.bak-${TIMESTAMP}"
    echo "Backed up existing .env to ${ENV_FILE}.bak-${TIMESTAMP}"
  fi

  local existing_user existing_pass existing_local_network existing_token
  existing_user="$(grep -E '^PIA_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_pass="$(grep -E '^PIA_PASS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_local_network="$(grep -E '^LOCAL_NETWORK=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_token="$(grep -E '^TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"

  local use_existing_local_network=false
  local pia_user pia_pass token

  print_section "PIA Credentials"

  prompt_required() {
    local prompt_text="$1"
    local default_value="${2-}"
    local value
    while true; do
      if [[ -n "$default_value" ]]; then
        read -r -p "$prompt_text [$default_value]: " value
        [[ -z "$value" ]] && value="$default_value"
      else
        read -r -p "$prompt_text: " value
      fi
      [[ -n "$value" ]] && { printf '%s\n' "$value"; return; }
      echo "Value required. Please enter a value."
    done
  }

  prompt_optional() {
    local prompt_text="$1"
    local default_value="${2-}"
    local value
    if [[ -n "$default_value" ]]; then
      read -r -p "$prompt_text [$default_value]: " value
      [[ -z "$value" ]] && value="$default_value"
    else
      read -r -p "$prompt_text (leave blank to skip for now): " value
    fi
    printf '%s\n' "$value"
  }

  ask_keep() {
    local prompt_text="$1"
    local reply
    while true; do
      read -r -p "$prompt_text [Y/n]: " reply
      if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then
        return 0
      elif [[ "$reply" =~ ^[Nn]$ ]]; then
        return 1
      else
        echo "Please answer y or n."
      fi
    done
  }

  if [[ -n "$existing_user" ]]; then
    if ask_keep "PIA_USER already set to '$existing_user'. Keep existing?"; then
      pia_user="$existing_user"
    else
      pia_user="$(prompt_required "Enter new PIA username")"
    fi
  else
    pia_user="$(prompt_required "Enter PIA username")"
  fi

  prompt_password() {
    local pia_pass_input
    while true; do
      read -r -p "Enter PIA password: " pia_pass_input
      if [[ -n "$pia_pass_input" ]]; then
        pia_pass="$pia_pass_input"
        return
      fi
      echo "Password required."
    done
  }

  if [[ -n "$existing_pass" ]]; then
    if ask_keep "PIA_PASS already set to '$existing_pass'. Keep existing?"; then
      pia_pass="$existing_pass"
    else
      prompt_password
    fi
  else
    prompt_password
  fi

  local local_network_subnets=()

  print_section "Networks"

  add_local_network_subnet() {
    local raw="$1"
    [[ -z "$raw" ]] && return
    IFS=',' read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      [[ -z "$part" ]] && continue
      if [[ ! "$part" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
        echo "Skipping invalid CIDR entry: $part"
        continue
      fi
      if [[ " ${local_network_subnets[*]} " != *" $part "* ]]; then
        local_network_subnets+=("$part")
      fi
    done
  }

  has_local_subnet() {
    local needle="$1"
    for sn in "${local_network_subnets[@]}"; do
      [[ "$sn" == "$needle" ]] && return 0
    done
    return 1
  }

  detect_local_database_path() {
    local compose_file=""
    local search_dirs=("$PWD")
    if [[ "${SCRIPT_DIR}" != "$PWD" ]]; then
      search_dirs+=("${SCRIPT_DIR}")
    fi

    for dir in "${search_dirs[@]}"; do
      for candidate in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        if [[ -f "${dir}/${candidate}" ]]; then
          compose_file="${dir}/${candidate}"
          break 2
        fi
      done
    done

    [[ -z "$compose_file" ]] && return

    local host_path
    host_path="$(awk '
      match($0, /^[[:space:]]*-[[:space:]]*([^:]+):\/app\/data\/database/, m) { print m[1]; exit }
    ' "$compose_file")"
    [[ -z "$host_path" ]] && return

    local compose_dir
    compose_dir="$(cd "$(dirname "$compose_file")" && pwd)"

    if [[ "$host_path" == ./* || "$host_path" == ../* ]]; then
      (cd "$compose_dir" && realpath "$host_path" 2>/dev/null) || true
    else
      realpath "$host_path" 2>/dev/null || printf '%s\n' "$host_path"
    fi
  }

  if [[ -n "$existing_local_network" ]]; then
    if ask_keep "LOCAL_NETWORK already set to '$existing_local_network'. Keep existing?"; then
      use_existing_local_network=true
    else
      add_local_network_subnet "$existing_local_network"
    fi
  fi

  detect_docker_subnet() {
    if ! command -v docker >/dev/null 2>&1; then
      echo "- docker not found; skipping Docker subnet detection."
      return
    fi
    local network_id
    network_id="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' vpn-pia 2>/dev/null | tr -d '\n' || true)"
    if [[ -z "$network_id" ]]; then
      network_id="$(docker compose ps -q vpn-pia 2>/dev/null | xargs -r docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null | head -n1 | tr -d '\n' || true)"
    fi
    [[ -z "$network_id" ]] && return
    local cidr
    cidr="$(docker network inspect "$network_id" --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null | head -n1 || true)"
    [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || return
    printf '%s\n' "$cidr"
  }

  local docker_subnet
  docker_subnet="$(detect_docker_subnet || true)"
  if [[ "$use_existing_local_network" != true ]]; then
    if [[ -n "$docker_subnet" ]]; then
      echo "- Detected Docker subnet for vpn-pia: $docker_subnet"
      add_local_network_subnet "$docker_subnet"
    else
      echo "- Docker subnet not detected automatically; update .env manually if needed."
    fi
  fi

  detect_local_subnet() {
    local iface
    iface="$(ip route | awk '/default/ {print $5; exit}')"
    [[ -z "$iface" ]] && return
    local cidr
    cidr="$(ip route show dev "$iface" 2>/dev/null | awk '!/default/ {print $1}' | head -n1)"
    [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || return
    printf '%s\n' "$cidr"
  }

  local local_subnet
  local_subnet="$(detect_local_subnet || true)"
  if [[ "$use_existing_local_network" != true ]]; then
    if [[ -n "$local_subnet" ]]; then
      echo "- Detected local subnet: $local_subnet"
      add_local_network_subnet "$local_subnet"
    else
      echo "- Local subnet not detected automatically."
    fi

    local default_local_network_value=""
    if [[ ${#local_network_subnets[@]} -gt 0 ]]; then
      default_local_network_value="$(IFS=','; echo "${local_network_subnets[*]}")"
    fi

    echo "Local network subnets (if you don't see your local subnet, please add it here):"
    if [[ -z "$default_local_network_value" ]]; then
      default_local_network_value="172.18.0.0/16"
    fi
    local local_network_input
    read -e -p "LOCAL_NETWORK=" -i "$default_local_network_value" local_network_input

    local_network_input="${local_network_input#LOCAL_NETWORK=}"
    local_network_input="${local_network_input#"${local_network_input%%[![:space:]]*}"}"
    local_network_input="${local_network_input%"${local_network_input##*[![:space:]]}"}"
    add_local_network_subnet "$local_network_input"

    local tailscale_cidr="100.64.0.0/10"
    if has_local_subnet "$tailscale_cidr"; then
      echo "- Tailscale subnet ($tailscale_cidr) already present; skipping prompt."
    else
      local tailscale_choice
      read -r -p "Include Tailscale subnet 100.64.0.0/10? [Y/n]: " tailscale_choice
      if [[ ! "$tailscale_choice" =~ ^[Nn]$ ]]; then
        add_local_network_subnet "$tailscale_cidr"
      fi
    fi
  fi

  local local_network_value
  if [[ "$use_existing_local_network" == true ]]; then
    local_network_value="$existing_local_network"
  else
    local_network_value="$(IFS=','; echo "${local_network_subnets[*]}")"
  fi

  print_section "Database & API"

  local extracted_token="" extracted_base=""
  local local_db_path
  local_db_path="$(detect_local_database_path || true)"
  if [[ -n "$local_db_path" ]]; then
    echo "- Local database path from compose: $local_db_path"
    local db_file="$local_db_path/app.db"
    local db_uri="file:$db_file?mode=ro&immutable=1"
    if [[ ! -f "$db_file" ]]; then
      echo "- Database ($db_file) not found. Likely first run and StremHU is not set up yet. Start the stack (docker compose up), complete StremHU setup, then rerun this setup to fill TOKEN/BASE_URL. Don't forget to restart docker after filling TOKEN/BASE_URL."
      exit 1
    fi
    if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$db_file" ]]; then
      extracted_base="$(sqlite3 -readonly -noheader "$db_uri" "SELECT address FROM settings WHERE id='global';" 2>/dev/null | head -n1 || true)"
      if [[ -n "$extracted_base" ]]; then
        echo "- Extracted BASE_URL from database: $extracted_base"
      else
        echo "- BASE_URL not found in database; will prompt."
      fi
      extracted_token="$(sqlite3 -readonly -noheader "$db_uri" "SELECT token FROM users WHERE user_role = 'admin';" 2>/dev/null | head -n1 || true)"
      if [[ -n "$extracted_token" ]]; then
        echo "- Extracted TOKEN from database: $extracted_token"
      else
        echo "- TOKEN not found in database; will prompt."
      fi
    else
      echo "- sqlite3 not available or $db_file not readable; cannot extract BASE_URL/TOKEN."
    fi
  else
    echo "- Compose file not found in $PWD or ${SCRIPT_DIR}; cannot auto-detect database path."
  fi

  if [[ -z "${BASE_URL-}" ]]; then
    if [[ -n "${base_env-}" ]]; then
      if ask_keep "BASE_URL already set to '$base_env'. Keep existing?"; then
        BASE_URL="$base_env"
      fi
    fi
    if [[ -z "$BASE_URL" && -n "$extracted_base" ]]; then
      if ask_keep "Use extracted BASE_URL ($extracted_base)?"; then
        BASE_URL="$extracted_base"
      fi
    fi
    if [[ -z "$BASE_URL" ]]; then
      BASE_URL="$(prompt_optional "Enter BASE_URL")"
      if [[ -z "$BASE_URL" ]]; then
        echo "- BASE_URL not provided; you can rerun setup after StremHU is configured to populate it."
      fi
    fi
  fi

  if [[ -z "${token-}" ]]; then
    if [[ -n "$existing_token" ]]; then
      if ask_keep "TOKEN already set to '$existing_token'. Keep existing?"; then
        token="$existing_token"
      fi
    fi
    if [[ -z "$token" && -n "$extracted_token" ]]; then
      if ask_keep "Use extracted TOKEN ($extracted_token)?"; then
        token="$extracted_token"
      fi
    fi
    if [[ -z "$token" ]]; then
      token="$(prompt_optional "Enter TOKEN" "$existing_token")"
      if [[ -z "$token" ]]; then
        echo "- TOKEN not provided; rerun setup after StremHU admin user exists to fill it."
      fi
    fi
  fi

  local preserved_lines=()
  if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line; do
      local trimmed
      trimmed="${line#"${line%%[![:space:]]*}"}"
      case "$trimmed" in
        PIA_USER=*|PIA_PASS=*|LOCAL_NETWORK=*|TOKEN=*|BASE_URL=*) continue ;;
        "# Private internet access VPN credentials:"*|\
        "# Allowed subnets for inbound access when FIREWALL=1."*|\
        "# Include:"*|\
        "#  - Docker network subnet the vpn container is attached to, usually 172.xxxxxx"*|\
        "#    Use this command to find out:"*|\
        "#     docker network inspect "*) continue ;;
        "#  - your host/LAN subnet for local access (example: 192.168.1.0/24)"*|\
        "#  - Tailscale subnet (100.64.0.0/10) if using Tailscale"*) continue ;;
      esac
      preserved_lines+=("$line")
    done < "$ENV_FILE"
  fi

  # Trim leading/trailing empty lines from preserved content
  while [[ ${#preserved_lines[@]} -gt 0 && -z "${preserved_lines[0]//[[:space:]]/}" ]]; do
    preserved_lines=("${preserved_lines[@]:1}")
  done
  while [[ ${#preserved_lines[@]} -gt 0 && -z "${preserved_lines[-1]//[[:space:]]/}" ]]; do
    unset 'preserved_lines[-1]'
  done

  {
    if [[ ${#preserved_lines[@]} -gt 0 ]]; then
      for ln in "${preserved_lines[@]}"; do
        printf "%s\n" "$ln"
      done
      printf "\n"
    fi
    printf "# Private internet access VPN credentials:\n\n"
    printf "PIA_USER=%s\n" "$pia_user"
    printf "PIA_PASS=%s\n\n" "$pia_pass"
    printf "# Allowed subnets for inbound access when FIREWALL=1.\n"
    printf "# Include:\n"
    printf "#  - Docker network subnet the vpn container is attached to, usually 172.xxxxxx\n"
    printf "#    Use this command to find out:\n"
    printf "#     docker network inspect \$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' vpn-pia)   --format '{{(index .IPAM.Config 0).Subnet}}'\n"
    printf "#  - your host/LAN subnet for local access (example: 192.168.1.0/24)\n"
    printf "#  - Tailscale subnet (100.64.0.0/10) if using Tailscale\n\n"
    printf "LOCAL_NETWORK=%s\n\n" "$local_network_value"
    printf "TOKEN=%s\n" "$token"
    printf "BASE_URL=%s\n" "$BASE_URL"
  } > "$ENV_FILE"

  echo ".env updated."
}

if [[ "${1-}" == "setup" ]]; then
  run_setup
  exit 0
fi

if [[ "${1-}" == "update" ]]; then
  maybe_update
fi

if [[ $# -lt 1 || -z "${1-}" ]]; then
  echo "Usage: $0 <port> | $0 setup | $0 update" >&2
  echo "  <port>   Update PIA forwarding port via API"
  echo "  setup    Run interactive .env setup (PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL)"
  echo "  update   Download latest pia-helper.sh and exit"
  exit 1
fi

if [[ -z "${token_env-}" ]]; then
  echo "TOKEN not found in .env; run '$0 setup' first to configure TOKEN." >&2
  exit 1
fi

if [[ -z "${base_env-}" ]]; then
  echo "BASE_URL not found in .env; run '$0 setup' first to configure BASE_URL." >&2
  exit 1
fi

TOKEN="$token_env"
BASE_URL="$base_env"

PORT="${1}"

SETTINGS_URL="${BASE_URL}/api/${TOKEN}/settings"

echo "PIA-VPN Port update: notifying ${BASE_URL} with port ${PORT}"

if ! curl \
  --fail \
  --silent \
  --show-error \
  --max-time 60 \
  --retry 5 \
  --retry-delay 30 \
  -X PUT \
  -H "Content-Type: application/json" \
  -d "{\"port\": ${PORT}}" \
  "${SETTINGS_URL}"
then
  status=$?
  echo "PIA-VPN Port update failed (curl exit ${status}) hitting ${SETTINGS_URL}. If the container just started, this can be normal while PIA settles." >&2
  exit 1
else
  echo "PIA-VPN Port update success (curl, pia-helper.sh)"
fi
