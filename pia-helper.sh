#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOOL_NAME="StremHU PIA Helper by madrian"
TOOL_VERSION="0.3"
UPDATE_URL="https://raw.githubusercontent.com/adrianmihalko/stremhu-pia-helper/refs/heads/main/pia-helper.sh"

TMP_DIRS=()
cleanup_tmp_dirs() {
  local d
  for d in ${TMP_DIRS[@]+"${TMP_DIRS[@]}"}; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d" || true
  done
}
trap cleanup_tmp_dirs EXIT

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

# ---------------------------------------------------------------------------
# Docker Compose file helpers
# ---------------------------------------------------------------------------

find_compose_file() {
  local dir candidate
  local dirs=("$PWD")
  if [[ "${SCRIPT_DIR}" != "$PWD" ]]; then
    dirs+=("${SCRIPT_DIR}")
  fi
  for dir in "${dirs[@]}"; do
    for candidate in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
      if [[ -f "${dir}/${candidate}" ]]; then
        printf '%s\n' "${dir}/${candidate}"
        return 0
      fi
    done
  done
  return 1
}

# Print the service name whose block contains the StremHU image/container name.
detect_compose_service() {
  local file="$1"
  awk '
    /^services:[[:space:]]*$/ { in_services=1; svc_indent=-1; next }
    in_services && /^[^[:space:]#]/ { in_services=0 }
    in_services && /^[ \t]*[A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ {
      ind=match($0,/[^ \t]/)-1
      if (svc_indent==-1) svc_indent=ind
      if (ind==svc_indent) {
        s=$0; sub(/:[[:space:]]*(#.*)?$/,"",s); sub(/^[ \t]+/,"",s); cur=s; next
      }
    }
    in_services && cur!="" && /image:[[:space:]]*["'"'"']?s4pp1\/stremhu-source/ { print cur; exit }
    in_services && cur!="" && /container_name:[[:space:]]*["'"'"']?stremhu-source/ { print cur; exit }
  ' "$file"
}

# Print the first service name found (fallback when StremHU cannot be identified).
detect_first_compose_service() {
  local file="$1"
  awk '
    /^services:[[:space:]]*$/ { in_services=1; next }
    in_services && /^[^[:space:]#]/ { in_services=0 }
    in_services && /^[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*$/ {
      s=$0; sub(/:[[:space:]]*$/,"",s); sub(/^[[:space:]]+/,"",s); print s; exit
    }
  ' "$file"
}

# Print the raw lines belonging to a service block.
extract_service_block() {
  local file="$1" target="$2"
  awk -v t="$target" '
    /^services:[[:space:]]*$/ { in_services=1; svc_indent=-1; in_block=0; next }
    in_services && /^[^[:space:]#]/ { in_services=0 }
    in_services && /^[ \t]*[A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ {
      ind=match($0,/[^ \t]/)-1
      if (svc_indent==-1) svc_indent=ind
      if (ind==svc_indent) {
        s=$0; sub(/:[[:space:]]*(#.*)?$/,"",s); sub(/^[ \t]+/,"",s)
        in_block=(s==t); next
      }
    }
    in_block { print }
  ' "$file"
}

# Print the first likely application port (container side, not the torrent port).
detect_app_port() {
  local block="$1"
  awk '
    BEGIN { inp=0 }
    function extract(s,   n,a,c) {
      if (s ~ /^[0-9]+$/) { return (s=="6881") ? "" : s }
      n=split(s,a,":")
      if (n < 2) return ""
      c=a[n]; sub(/\/.*/,"",c)
      if (c+0>0 && c!="6881") return c
      return ""
    }
    /^[[:space:]]*ports:[[:space:]]*$/ { inp=1; next }
    /^[[:space:]]*ports:[[:space:]]*.+/ {
      l=$0; sub(/.*ports:[[:space:]]*/,"",l)
      gsub(/\[/,"",l); gsub(/\]/,"",l); gsub(/["'"'"']/,"",l); gsub(/[[:space:]]/,"",l)
      n=split(l,a,","); for(i=1;i<=n;i++){ p=extract(a[i]); if(p!=""){ print p; exit } }
      next
    }
    inp && /^[[:space:]]*-/ {
      l=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",l)
      gsub(/["'"'"']/,"",l); sub(/[[:space:]]*#.*/,"",l)
      p=extract(l); if(p!=""){ print p; exit }
      next
    }
    inp && /target:[[:space:]]*[0-9]+/ {
      l=$0; sub(/.*target:[[:space:]]*/,"",l); sub(/[^0-9].*/,"",l)
      if(l!="6881"){ print l; exit }
      next
    }
    inp && /^[[:space:]]*(published|protocol|mode)[[:space:]]*:/ { next }
    inp && /^[[:space:]]*[A-Za-z0-9_.-]+:/ { inp=0 }
  ' <<< "$block"
}

# Print each candidate volume mapping as: <source>|<target>
detect_volume_mappings() {
  local block="$1"
  awk '
    BEGIN { inv=0; cur_type=""; cur_src=""; cur_tgt="" }
    /^[[:space:]]*volumes:[[:space:]]*$/ { inv=1; next }
    inv && /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ {
      l=$0; sub(/.*type:[[:space:]]*/,"",l); gsub(/["'"'"']/,"",l); cur_type=l; cur_src=""; cur_tgt=""; next
    }
    inv && /^[[:space:]]*(source|src)[[:space:]]*:/ {
      l=$0; sub(/.*(source|src)[[:space:]]*:[[:space:]]*/,"",l); gsub(/["'"'"']/,"",l); cur_src=l; next
    }
    inv && /^[[:space:]]*target:[[:space:]]*/ {
      l=$0; sub(/.*target:[[:space:]]*/,"",l); gsub(/["'"'"']/,"",l); cur_tgt=l
      if (cur_tgt != "") { print cur_src "|" cur_tgt }
      next
    }
    inv && /^[[:space:]]*-/ {
      l=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",l); gsub(/["'"'"']/,"",l); sub(/[[:space:]]*#.*/,"",l)
      if (l ~ /:/) {
        src=l; sub(/:.*/,"",src)
        tgt=l; sub(/^[^:]*:/,"",tgt); sub(/:.*/,"",tgt)
        print src "|" tgt
      }
      next
    }
    inv && /^[[:space:]]*[A-Za-z0-9_.-]+:/ { inv=0 }
  ' <<< "$block"
}

# Given a "source|target" mapping, resolve DB location: <mode>|<source_or_path>|<subpath>
resolve_db_location() {
  local source="$1" target="$2"
  local subpath=""
  case "$target" in
    /app/data/system) subpath="database/app.db" ;;
    /app/data) subpath="system/database/app.db" ;;
    *) return 1 ;;
  esac
  [[ -z "$source" ]] && return 1
  local mode="volume"
  case "$source" in
    /*|./*|../*) mode="bind" ;;
  esac
  printf '%s|%s|%s\n' "$mode" "$source" "$subpath"
}

# Copy the StremHU database to a temporary file and print its path.
copy_database() {
  local compose_file="$1" service="$2" mode="$3" source="$4" subpath="$5"
  local compose_dir tmp
  compose_dir="$(cd "$(dirname "$compose_file")" && pwd)"
  tmp="$(mktemp -d)"
  TMP_DIRS+=("$tmp")

  if [[ "$mode" == "bind" ]]; then
    local base
    if [[ "$source" == ./* || "$source" == ../* ]]; then
      base="$(cd "$compose_dir" && realpath "$source" 2>/dev/null || true)"
    else
      base="$(realpath "$source" 2>/dev/null || printf '%s' "$source")"
    fi
    [[ -z "$base" ]] && return 1
    local dbfile="$base/$subpath"
    if [[ -f "$dbfile" ]]; then
      printf '%s\n' "$dbfile"
      return 0
    fi
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  local container_id=""
  container_id="$(docker compose -f "$compose_file" ps -q "$service" 2>/dev/null | head -n1 || true)"
  if [[ -z "$container_id" ]]; then
    container_id="$(docker ps -aq -f "name=^/${service}$" 2>/dev/null | head -n1 || true)"
  fi
  if [[ -n "$container_id" ]]; then
    if docker cp "${container_id}:/app/data/system/database/app.db" "$tmp/app.db" >/dev/null 2>&1; then
      printf '%s\n' "$tmp/app.db"
      return 0
    fi
  fi

  local image="alpine:3"
  if docker run --rm --entrypoint cp -v "${source}:/src" -v "${tmp}:/out" "$image" "/src/$subpath" "/out/app.db" >/dev/null 2>&1; then
    if [[ -f "$tmp/app.db" ]]; then
      printf '%s\n' "$tmp/app.db"
      return 0
    fi
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

run_setup() {
  local TIMESTAMP
  TIMESTAMP="$(date +%Y%m%d%H%M%S)"

  local compose_file=""
  compose_file="$(find_compose_file || true)"
  local ENV_FILE="$ENV_PATH"
  if [[ -n "$compose_file" ]]; then
    ENV_FILE="$(cd "$(dirname "$compose_file")" && pwd)/.env"
  fi

  ensure_rw_target() {
    local target="$1" label="$2"
    if [[ -e "$target" ]]; then
      [[ -r "$target" ]] || { echo "Error: $label ($target) is not readable." >&2; exit 1; }
      [[ -w "$target" ]] || { echo "Error: $label ($target) is not writable." >&2; exit 1; }
    else
      local parent; parent="$(dirname "$target")"
      [[ -w "$parent" ]] || { echo "Error: parent dir for $label ($parent) not writable." >&2; exit 1; }
    fi
  }

  print_section() { echo; echo "== $1 =="; }

  ask_keep() {
    local prompt_text="$1" reply
    while true; do
      read -r -p "$prompt_text [Y/n]: " reply
      if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then return 0; fi
      if [[ "$reply" =~ ^[Nn]$ ]]; then return 1; fi
      echo "Please answer y or n."
    done
  }

  prompt_required() {
    local prompt_text="$1" default_value="${2-}" value
    while true; do
      if [[ -n "$default_value" ]]; then
        read -r -p "$prompt_text [$default_value]: " value
        [[ -z "$value" ]] && value="$default_value"
      else
        read -r -p "$prompt_text: " value
      fi
      [[ -n "$value" ]] && { printf '%s\n' "$value"; return; }
      echo "Value required."
    done
  }

  prompt_optional() {
    local prompt_text="$1" default_value="${2-}" value
    if [[ -n "$default_value" ]]; then
      read -r -p "$prompt_text [$default_value]: " value
      [[ -z "$value" ]] && value="$default_value"
    else
      read -r -p "$prompt_text (leave blank to skip for now): " value
    fi
    printf '%s\n' "$value"
  }

  echo "${TOOL_NAME} v${TOOL_VERSION}"
  ensure_rw_target "$ENV_FILE" ".env file"

  if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" "${ENV_FILE}.bak-${TIMESTAMP}"
    chmod 600 "${ENV_FILE}.bak-${TIMESTAMP}" 2>/dev/null || true
    echo "Backed up existing .env to ${ENV_FILE}.bak-${TIMESTAMP}"
  fi

  local existing_user="" existing_pass="" existing_local_network="" existing_token=""
  local existing_loc="" existing_tz="" existing_selfsigned=""
  existing_user="$(grep -E '^PIA_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_pass="$(grep -E '^PIA_PASS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_local_network="$(grep -E '^LOCAL_NETWORK=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_token="$(grep -E '^TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_loc="$(grep -E '^LOC=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_tz="$(grep -E '^TZ=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
  existing_selfsigned="$(grep -E '^SELFSIGNED=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"

  local pia_user="" pia_pass=""

  print_section "PIA Credentials"
  if [[ -n "$existing_user" ]] && ask_keep "PIA_USER already set to '$existing_user'. Keep existing?"; then
    pia_user="$existing_user"
  else
    pia_user="$(prompt_required "Enter PIA username")"
  fi

  if [[ -n "$existing_pass" ]] && ask_keep "PIA_PASS already set. Keep existing?"; then
    pia_pass="$existing_pass"
  else
    while true; do
      read -r -s -p "Enter PIA password: " pia_pass
      echo
      [[ -n "$pia_pass" ]] && break
      echo "Password required."
    done
  fi

  # -- Networks -------------------------------------------------------------
  local local_network_subnets=()
  print_section "Networks"

  add_local_network_subnet() {
    local raw="$1" part
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
    local needle="$1" sn
    for sn in "${local_network_subnets[@]}"; do [[ "$sn" == "$needle" ]] && return 0; done
    return 1
  }

  detect_docker_subnet() {
    command -v docker >/dev/null 2>&1 || return 1
    local network_id cidr
    network_id="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' vpn-pia 2>/dev/null | tr -d '\n' || true)"
    if [[ -z "$network_id" ]]; then
      network_id="$(docker compose ps -q vpn-pia 2>/dev/null | xargs -r docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null | head -n1 | tr -d '\n' || true)"
    fi
    [[ -z "$network_id" ]] && return 1
    cidr="$(docker network inspect "$network_id" --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null | head -n1 || true)"
    [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || return 1
    printf '%s\n' "$cidr"
  }

  detect_local_subnet() {
    local iface cidr
    iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
    [[ -z "$iface" ]] && return 1
    cidr="$(ip route show dev "$iface" 2>/dev/null | awk '!/default/ {print $1}' | head -n1)"
    [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || return 1
    printf '%s\n' "$cidr"
  }

  local use_existing_local_network=false
  if [[ -n "$existing_local_network" ]]; then
    if ask_keep "LOCAL_NETWORK already set to '$existing_local_network'. Keep existing?"; then
      use_existing_local_network=true
    else
      add_local_network_subnet "$existing_local_network"
    fi
  fi

  local local_network_value=""
  if [[ "$use_existing_local_network" == true ]]; then
    local_network_value="$existing_local_network"
  else
    local docker_subnet local_subnet
    docker_subnet="$(detect_docker_subnet || true)"
    if [[ -n "$docker_subnet" ]]; then
      echo "- Detected Docker subnet: $docker_subnet"
      add_local_network_subnet "$docker_subnet"
    else
      echo "- Docker subnet not detected automatically."
    fi
    local_subnet="$(detect_local_subnet || true)"
    if [[ -n "$local_subnet" ]]; then
      echo "- Detected local subnet: $local_subnet"
      add_local_network_subnet "$local_subnet"
    else
      echo "- Local subnet not detected automatically."
    fi

    local default_local_network_value=""
    if [[ ${#local_network_subnets[@]} -gt 0 ]]; then
      default_local_network_value="$(IFS=','; echo "${local_network_subnets[*]}")"
    else
      default_local_network_value="172.18.0.0/16"
    fi
    local local_network_input
    read -e -p "LOCAL_NETWORK=" -i "$default_local_network_value" local_network_input
    local_network_input="${local_network_input#LOCAL_NETWORK=}"
    add_local_network_subnet "$local_network_input"

    local tailscale_cidr="100.64.0.0/10"
    if has_local_subnet "$tailscale_cidr"; then
      echo "- Tailscale subnet already present."
    else
      local tailscale_choice
      read -r -p "Include Tailscale subnet 100.64.0.0/10? [Y/n]: " tailscale_choice
      [[ ! "$tailscale_choice" =~ ^[Nn]$ ]] && add_local_network_subnet "$tailscale_cidr"
    fi
    local_network_value="$(IFS=','; echo "${local_network_subnets[*]}")"
  fi

  # -- StremHU readiness ----------------------------------------------------
  print_section "StremHU Source"
  if ! ask_keep "Was StremHU Source already set up and configured (admin user + network)?"; then
    echo
    echo "Setup a VPN helper requires a working, configured StremHU Source installation."
    echo "Please do the following first:"
    echo "  1) docker compose up -d"
    echo "  2) Finish the StremHU web setup (admin user, network, torrent port)"
    echo "  3) docker compose down"
    echo "  4) Run './pia-helper.sh setup' again"
    exit 1
  fi

  local containers_running=false
  if command -v docker >/dev/null 2>&1; then
    local svc_hint="stremhu-source"
    if [[ -n "$compose_file" ]]; then
      svc_hint="$(detect_compose_service "$compose_file" || true)"
      [[ -z "$svc_hint" ]] && svc_hint="stremhu-source"
    fi
    local running_names
    running_names="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"
    if grep -qx "$svc_hint" <<< "$running_names" \
      || grep -qx "vpn-pia" <<< "$running_names" \
      || grep -qx "speedtest-app" <<< "$running_names"; then
      containers_running=true
    fi
  fi
  if [[ "$containers_running" == true ]]; then
    echo
    echo "The StremHU stack is currently running. Stop it before continuing, because"
    echo "the container network mode and published ports will change:"
    if [[ -n "$compose_file" ]]; then
      echo "  docker compose -f \"$compose_file\" down"
    else
      echo "  docker compose down"
    fi
    local _stopped_reply
    while true; do
      read -r -p "Press Enter once the containers are stopped (or type 'skip' to continue anyway): " _stopped_reply
      if [[ -z "$_stopped_reply" || "$_stopped_reply" == "skip" ]]; then
        break
      fi
      echo "Press Enter to continue, or type 'skip'."
    done
  fi

  # -- Compose + database ---------------------------------------------------
  print_section "Database & API"

  local service_name="" api_port="" db_volume_mode="" db_volume_source="" db_subpath=""

  if [[ -n "$compose_file" ]]; then
    echo "- Compose file: $compose_file"
    service_name="$(detect_compose_service "$compose_file" || true)"
    if [[ -z "$service_name" ]]; then
      service_name="$(detect_first_compose_service "$compose_file" || true)"
      [[ -n "$service_name" ]] && echo "- StremHU service not identified by image; using '$service_name'."
    fi
    [[ -z "$service_name" ]] && service_name="stremhu-source"

    local block
    block="$(extract_service_block "$compose_file" "$service_name" || true)"
    api_port="$(detect_app_port "$block" || true)"

    local mapping best_system="" best_data=""
    while IFS= read -r mapping; do
      [[ -z "$mapping" ]] && continue
      local src="${mapping%%|*}" tgt="${mapping#*|}"
      case "$tgt" in
        /app/data/system) best_system="$src" ;;
        /app/data) best_data="$src" ;;
      esac
    done < <(detect_volume_mappings "$block" || true)

    if [[ -n "$best_system" ]]; then
      db_volume_source="$best_system"
      db_subpath="database/app.db"
    elif [[ -n "$best_data" ]]; then
      db_volume_source="$best_data"
      db_subpath="system/database/app.db"
    fi
    if [[ -n "$db_volume_source" ]]; then
      case "$db_volume_source" in
        /*|./*|../*) db_volume_mode="bind" ;;
        *) db_volume_mode="volume" ;;
      esac
      echo "- Detected data mount ($db_volume_mode): $db_volume_source -> /$([[ -n "$best_system" ]] && echo app/data/system || echo app/data)"
    else
      echo "- Could not detect the StremHU data volume automatically."
    fi
  else
    echo "- Compose file not found in $PWD or ${SCRIPT_DIR}."
  fi

  local api_port_default="${api_port:-7070}"
  echo "- API port (from compose, default 7070): $api_port_default"

  local extracted_token="" extracted_base="" selfsigned="${existing_selfsigned:-false}"
  local db_copy=""
  if [[ -n "$db_volume_source" && -n "$db_subpath" ]]; then
    db_copy="$(copy_database "$compose_file" "$service_name" "$db_volume_mode" "$db_volume_source" "$db_subpath" || true)"
  fi

  if [[ -n "$db_copy" && -f "$db_copy" ]]; then
    echo "- Reading database: $db_copy"
    if command -v sqlite3 >/dev/null 2>&1; then
      local db_uri="file:$db_copy?mode=ro&immutable=1"
      extracted_token="$(sqlite3 -readonly -noheader "$db_uri" "SELECT api_key FROM users WHERE role_id='admin' LIMIT 1;" 2>/dev/null | head -n1 || true)"
      local net_row
      net_row="$(sqlite3 -readonly -noheader -separator '|' "$db_uri" "SELECT json_extract(value,'\$.mode'), json_extract(value,'\$.host'), json_extract(value,'\$.ip'), json_extract(value,'\$.self_signed') FROM settings WHERE key='network';" 2>/dev/null | head -n1 || true)"
      local net_mode net_host net_ip net_ss
      IFS='|' read -r net_mode net_host net_ip net_ss <<< "$net_row"
      if [[ -n "$net_row" ]]; then
        if [[ "$net_ss" == "1" || "$net_ss" == "true" ]]; then
          selfsigned="true"
        else
          selfsigned="false"
        fi
      fi
      local scheme="https"
      [[ "$net_mode" == "manual" ]] && scheme="http"
      local use_host="${net_host:-$net_ip}"
      if [[ -n "$use_host" ]]; then
        extracted_base="${scheme}://${use_host}:${api_port_default}"
        echo "- Derived BASE_URL from database: $extracted_base"
      fi
      if [[ -n "$extracted_token" ]]; then
        echo "- Extracted TOKEN from database: ${extracted_token:0:8}..."
      else
        echo "- TOKEN not found in database; will prompt."
      fi
    else
      echo "- sqlite3 not available; cannot extract TOKEN/BASE_URL."
    fi
  else
    echo "- Database not found. If StremHU has not been set up yet, start it once, configure it, then rerun setup."
  fi

  BASE_URL=""
  if [[ -n "${base_env-}" ]] && ask_keep "BASE_URL already set to '$base_env'. Keep existing?"; then
    BASE_URL="$base_env"
  fi
  if [[ -z "$BASE_URL" && -n "$extracted_base" ]] && ask_keep "Use detected BASE_URL ($extracted_base)?"; then
    BASE_URL="$extracted_base"
  fi
  if [[ -z "$BASE_URL" ]]; then
    BASE_URL="$(prompt_optional "Enter BASE_URL")"
    [[ -z "$BASE_URL" ]] && echo "- BASE_URL not provided; rerun setup later to populate it."
  fi

  local token=""
  if [[ -n "$existing_token" ]] && ask_keep "TOKEN already set. Keep existing?"; then
    token="$existing_token"
  fi
  if [[ -z "$token" && -n "$extracted_token" ]] && ask_keep "Use extracted TOKEN (${extracted_token:0:8}...)?"; then
    token="$extracted_token"
  fi
  if [[ -z "$token" ]]; then
    token="$(prompt_optional "Enter TOKEN")"
    [[ -z "$token" ]] && echo "- TOKEN not provided; rerun setup after StremHU admin user exists."
  fi

  # -- Misc -----------------------------------------------------------------
  local loc tz
  loc="$(prompt_required "PIA location (LOC)" "${existing_loc:-hungary}")"
  tz="$(prompt_required "Timezone (TZ)" "${existing_tz:-Europe/Budapest}")"

  # -- Write .env -----------------------------------------------------------
  local preserved_lines=()
  if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line; do
      local trimmed
      trimmed="${line#"${line%%[![:space:]]*}"}"
      case "$trimmed" in
        PIA_USER=*|PIA_PASS=*|LOCAL_NETWORK=*|TOKEN=*|BASE_URL=*|LOC=*|TZ=*|SELFSIGNED=*) continue ;;
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

  while [[ ${#preserved_lines[@]} -gt 0 && -z "${preserved_lines[0]//[[:space:]]/}" ]]; do
    preserved_lines=("${preserved_lines[@]:1}")
  done
  while [[ ${#preserved_lines[@]} -gt 0 && -z "${preserved_lines[-1]//[[:space:]]/}" ]]; do
    unset 'preserved_lines[-1]'
  done

  {
    if [[ ${#preserved_lines[@]} -gt 0 ]]; then
      for ln in "${preserved_lines[@]}"; do printf "%s\n" "$ln"; done
      printf "\n"
    fi
    printf "# Private internet access VPN credentials:\n\n"
    printf "PIA_USER=%s\n" "$pia_user"
    printf "PIA_PASS=%s\n\n" "$pia_pass"
    printf "# Allowed subnets for inbound access when FIREWALL=1.\n"
    printf "# Include the Docker network subnet the VPN container is attached to,\n"
    printf "# your host/LAN subnet, and optionally the Tailscale subnet (100.64.0.0/10).\n\n"
    printf "LOCAL_NETWORK=%s\n\n" "$local_network_value"
    printf "TOKEN=%s\n" "$token"
    printf "BASE_URL=%s\n" "$BASE_URL"
    printf "LOC=%s\n" "$loc"
    printf "TZ=%s\n" "$tz"
    printf "SELFSIGNED=%s\n" "$selfsigned"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  echo ".env updated."

  # -- Generate override ----------------------------------------------------
  local env_file_abs script_abs
  env_file_abs="$(readlink -f "$ENV_FILE" 2>/dev/null || printf '%s' "$ENV_FILE")"
  script_abs="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "$0")"
  generate_override "$compose_file" "$service_name" "$api_port_default" "$loc" "$tz" "$env_file_abs" "$script_abs"

  echo
  if [[ -z "$token" || -z "$BASE_URL" ]]; then
    echo "Setup incomplete: TOKEN/BASE_URL missing. Finish StremHU setup and rerun './pia-helper.sh setup'."
    exit 1
  fi
  echo "Setup complete. Start the stack to apply the VPN routing."
}

# ---------------------------------------------------------------------------
# Override generation
# ---------------------------------------------------------------------------

generate_override() {
  local compose_file="$1" service="$2" api_port="$3" loc="$4" tz="$5" env_file_abs="$6" script_abs="$7"

  local target_dir="$PWD" override_name="docker-compose.override.yml"
  if [[ -n "$compose_file" ]]; then
    target_dir="$(cd "$(dirname "$compose_file")" && pwd)"
  fi

  local cand foreign=false
  for cand in docker-compose.override.yml compose.override.yml; do
    if [[ -f "${target_dir}/${cand}" ]] && ! grep -q "Generated by pia-helper.sh" "${target_dir}/${cand}" 2>/dev/null; then
      foreign=true
    fi
  done
  if [[ "$foreign" == true ]]; then
    override_name="compose.pia.yml"
  elif [[ -f "${target_dir}/compose.pia.yml" ]] && grep -q "Generated by pia-helper.sh" "${target_dir}/compose.pia.yml" 2>/dev/null; then
    override_name="compose.pia.yml"
  fi

  local override_path="${target_dir}/${override_name}"

  mkdir -p "${target_dir}/pia-compose/pia" "${target_dir}/pia-compose/pia-shared"

  cat > "$override_path" <<'YAML'
# Generated by pia-helper.sh - PIA VPN injection for an existing StremHU Source stack.
# Usage: docker compose up -d
# Requires Docker Compose >= 2.24 (for the "!reset" tag on ports).
services:
  vpn-pia:
    image: thrnz/docker-wireguard-pia
    container_name: vpn-pia
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.default.disable_ipv6=1
      - net.ipv6.conf.all.disable_ipv6=1
      - net.ipv6.conf.lo.disable_ipv6=1
    environment:
      - DEBUG=0
      - TZ=__TZ__
      - LOC=__LOC__
      - USER=${PIA_USER}
      - PASS=${PIA_PASS}
      - LOCAL_NETWORK=${LOCAL_NETWORK}
      - KEEPALIVE=25
      - VPNDNS=1.1.1.1,1.0.0.1
      - PORT_FORWARDING=1
      - PORT_FILE=/pia-shared/port.dat
      - PORT_FILE_CLEANUP=0
      - PORT_PERSIST=1
      - FIREWALL=1
      - ACTIVE_HEALTHCHECKS=1
      - HEALTHCHECK_PING_TARGET=www.google.com,1.1.1.1
      - HEALTHCHECK_PING_TIMEOUT=5
      - RECONNECT=1
      - MONITOR_INTERVAL=60
      - MONITOR_RETRIES=3
      - PORT_SCRIPT=/pia-helper.sh
    volumes:
      - ./pia-compose/pia:/pia
      - ./pia-compose/pia-shared:/pia-shared
      - __ENV_FILE__:/.env:ro
      - __SCRIPT_PATH__:/pia-helper.sh
    ports:
      - "__API_PORT__:__API_PORT__"
      - "6881:6881"
      - "6881:6881/udp"
      - "3004:5000"
    healthcheck:
      test:
        - CMD-SHELL
        - curl -fsS --max-time 5 https://api.ipify.org >/dev/null || exit 1
      interval: 15s
      timeout: 7s
      retries: 10
      start_period: 30s
    restart: unless-stopped
  speedtest-app:
    image: adriankoooo/speedtest-app:latest
    container_name: speedtest-app
    depends_on:
      vpn-pia:
        condition: service_healthy
    network_mode: service:vpn-pia
    environment:
      - TZ=__TZ__
    volumes:
      - ./pia-compose/pia-shared/port.dat:/port.dat:ro
    restart: unless-stopped
  __SERVICE__:
    ports: !reset []
    network_mode: service:vpn-pia
    depends_on:
      vpn-pia:
        condition: service_healthy
YAML

  sed -i \
    -e "s|__SERVICE__|${service}|g" \
    -e "s|__API_PORT__|${api_port}|g" \
    -e "s|__TZ__|${tz}|g" \
    -e "s|__LOC__|${loc}|g" \
    -e "s|__ENV_FILE__|${env_file_abs}|g" \
    -e "s|__SCRIPT_PATH__|${script_abs}|g" \
    "$override_path"

  echo
  echo "Override written to: $override_path"
  if [[ "$override_name" == "docker-compose.override.yml" ]]; then
    echo "Start with: docker compose up -d"
  else
    echo "Start with: docker compose -f docker-compose.yml -f ${override_name} up -d"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ENV_PATH=".env"
if [[ ! -f "$ENV_PATH" && -f "${SCRIPT_DIR}/.env" ]]; then
  ENV_PATH="${SCRIPT_DIR}/.env"
fi
if [[ ! -f "$ENV_PATH" && -f "/.env" ]]; then
  ENV_PATH="/.env"
fi

token_env=""
base_env=""
selfsigned_env="false"
if [[ -f "$ENV_PATH" ]]; then
  token_env="$(grep -E '^TOKEN=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  base_env="$(grep -E '^BASE_URL=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  selfsigned_env="$(grep -E '^SELFSIGNED=' "$ENV_PATH" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
fi
if [[ -z "$token_env" && -n "${TOKEN-}" ]]; then token_env="$TOKEN"; fi
if [[ -z "$base_env" && -n "${BASE_URL-}" ]]; then base_env="$BASE_URL"; fi
[[ -z "$selfsigned_env" ]] && selfsigned_env="false"

case "${1-}" in
  setup)
    run_setup
    exit 0
    ;;
  update)
    maybe_update
    ;;
  "")
    echo "Usage: $0 <port> | $0 setup | $0 update" >&2
    echo "  <port>   Update PIA forwarding port via API"
    echo "  setup    Run interactive setup (PIA creds, networks, override generation)"
    echo "  update   Download latest pia-helper.sh and exit"
    exit 1
    ;;
esac

if [[ -z "${token_env-}" ]]; then
  echo "TOKEN not found in .env; run '$0 setup' first." >&2
  exit 1
fi
if [[ -z "${base_env-}" ]]; then
  echo "BASE_URL not found in .env; run '$0 setup' first." >&2
  exit 1
fi

TOKEN="$token_env"
BASE_URL="$base_env"
PORT="${1}"

SETTINGS_URL="${BASE_URL}/api/${TOKEN}/relay/settings"

if [[ "$selfsigned_env" == "true" || "$selfsigned_env" == "1" ]]; then
  CURL_INSECURE=(-k)
else
  CURL_INSECURE=()
fi

echo "PIA-VPN Port update: notifying ${BASE_URL} with port ${PORT}"

if ! curl \
  --fail \
  --silent \
  --show-error \
  ${CURL_INSECURE[@]+"${CURL_INSECURE[@]}"} \
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
