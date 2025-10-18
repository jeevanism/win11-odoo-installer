#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_CYAN=$'\033[36m'
  COLOR_GREEN=$'\033[32m'
  COLOR_RED=$'\033[31m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_MAGENTA=$'\033[35m'
  COLOR_WHITE=$'\033[37m'
else
  COLOR_RESET=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_YELLOW=""
  COLOR_MAGENTA=""
  COLOR_WHITE=""
fi

styled_echo() {
  local color="$1"
  shift
  printf "%b%s%b\n" "$color" "$*" "$COLOR_RESET"
}

log_step() { styled_echo "$COLOR_CYAN" "$*"; }
log_info() { styled_echo "$COLOR_WHITE" "$*"; }
log_success() { styled_echo "$COLOR_GREEN" "$*"; }
log_warn() { styled_echo "$COLOR_YELLOW" "$*"; }
log_error() { styled_echo "$COLOR_RED" "$*"; }

declare -A ODOO_VERSIONS=(
  ["19.0"]="3.12"
  ["18.0"]="3.12"
  ["17.0"]="3.11"
  ["16.0"]="3.10"
)

ODOO_REPO_URL="https://github.com/odoo/odoo.git"
ODOO_REQUIREMENTS_URL_TEMPLATE="https://raw.githubusercontent.com/odoo/odoo/%s/requirements.txt"

SELECTED_VERSION=""
REQUIRED_PYTHON_VERSION=""

check_prerequisites() {
  log_step "Step 1: Checking prerequisites (git, uv)..."

  if ! command -v git >/dev/null 2>&1; then
    log_error "Git is not installed or not in PATH. Please install Git before proceeding."
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log_error "Neither 'curl' nor 'wget' is available. Install one of them to download requirements."
    exit 1
  fi

  if ! command -v uv >/dev/null 2>&1; then
    log_warn "Warning: 'uv' is not installed. Attempting to install via 'python -m pip'..."

    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
      python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
      python_cmd="python"
    else
      log_error "Python is not available. Install Python before running this installer."
      exit 1
    fi

    if "$python_cmd" -m pip install --user uv; then
      export PATH="$HOME/.local/bin:$PATH"
      log_success " [OK] 'uv' installed successfully."
    else
      log_error "Failed to install 'uv'. Please install it manually (pip install uv)."
      exit 1
    fi

    if ! command -v uv >/dev/null 2>&1; then
      log_error "'uv' is still not in PATH. Add '$HOME/.local/bin' to your PATH and retry."
      exit 1
    fi
  fi

  log_success " [OK] All prerequisites found (git and uv)."
}

select_odoo_version() {
  log_step "Step 2: Select Odoo version"

  local versions=()
  while IFS= read -r version; do
    versions+=("$version")
  done < <(printf "%s\n" "${!ODOO_VERSIONS[@]}" | sort -r)

  local index=1
  for version in "${versions[@]}"; do
    local python="${ODOO_VERSIONS[$version]}"
    styled_echo "$COLOR_WHITE" " [$index] Odoo $version (Python $python)"
    ((index++))
  done

  local selection=""
  while true; do
    read -rp "Enter the number for the Odoo version you want to install: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#versions[@]} )); then
      SELECTED_VERSION="${versions[selection-1]}"
      REQUIRED_PYTHON_VERSION="${ODOO_VERSIONS[$SELECTED_VERSION]}"
      log_success " [INFO] Selected Odoo Version: $SELECTED_VERSION"
      break
    else
      log_warn "Invalid selection. Please enter a valid number."
    fi
  done
}

download_requirements_only() {
  local clone_dir="$1"

  log_step "Step 3 (prep): Downloading requirements.txt and creating mock directories."

  mkdir -p "$clone_dir"

  local requirements_url
  requirements_url=$(printf "$ODOO_REQUIREMENTS_URL_TEMPLATE" "$SELECTED_VERSION")

  log_info "Downloading requirements.txt from: $requirements_url"

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL "$requirements_url" -o "$clone_dir/requirements.txt"; then
      log_error "Failed to download requirements.txt for Odoo $SELECTED_VERSION."
      exit 1
    fi
  else
    if ! wget -q -O "$clone_dir/requirements.txt" "$requirements_url"; then
      log_error "Failed to download requirements.txt for Odoo $SELECTED_VERSION."
      exit 1
    fi
  fi

  mkdir -p "$clone_dir/odoo/addons" "$clone_dir/addons"
  log_info " [INFO] Created mock addons directories for configuration."
}

prepare_psycopg_fallback() {
  local requirements_file="$1/requirements.txt"

  if command -v pg_config >/dev/null 2>&1; then
    return
  fi

  if [[ -f "$requirements_file" ]] && grep -Eq '^psycopg2([^-\r\n])' "$requirements_file"; then
    log_warn "pg_config not found; switching requirements to use psycopg2-binary."
    sed -i.bak -E 's/^psycopg2([^-\r\n][^#\r\n]*)/psycopg2-binary\1/' "$requirements_file"
    log_info " [INFO] Updated requirements.txt (backup at requirements.txt.bak)."
  fi
}

prepare_reportlab_fallback() {
  local requirements_file="$1/requirements.txt"

  if [[ ! -f "$requirements_file" ]]; then
    return
  fi

  if grep -Eq '^reportlab==3\.5\.59' "$requirements_file"; then
    log_warn "Forcing reportlab to a newer wheel-friendly version (3.6.13) to avoid C extension build failures."
    sed -i.bak -E 's/^reportlab==3\.5\.59/reportlab==3.6.13/' "$requirements_file"
    log_info " [INFO] Updated requirements.txt (backup kept as requirements.txt.bak)."
  fi
}

prepare_gevent_cython_fallback() {
  local requirements_file="$1/requirements.txt"

  if [[ ! -f "$requirements_file" ]]; then
    return
  fi

  if grep -Eq '^gevent==21\.8\.0' "$requirements_file"; then
    log_warn "Replacing gevent 21.8.0 with wheel-friendly 22.10.2 for Python 3.10."
    sed -i.bak -E "s/^gevent==21\\.8\\.0/gevent==22.10.2/" "$requirements_file"
    log_warn "Aligning greenlet requirement with gevent fallback (greenlet 2.0.2)."
    sed -i -E "s/^greenlet==1\\.1\\.2(.*python_version *<= *'3\\.10'.*)/greenlet==2.0.2\1/" "$requirements_file"
    if ! grep -Eq '^Cython(<|==)' "$requirements_file"; then
      log_warn "Pinning Cython<3 alongside gevent fallback to satisfy build tooling."
      local tmp_file
      tmp_file="$(mktemp)"
      printf "Cython<3\n" > "$tmp_file"
      cat "$requirements_file" >> "$tmp_file"
      mv "$tmp_file" "$requirements_file"
      log_info " [INFO] Added 'Cython<3' to requirements.txt (placed at top)."
    fi
  fi
}

generate_odoo_conf() {
  local base_install_path="$1"
  local odoo_clone_dir="$2"

  log_step "Step 6: Generating odoo.conf file..."

  local major="${SELECTED_VERSION%%.*}"
  local http_port="80${major}"
  local longpolling_port="8072"

  local conf_file="$base_install_path/odoo.conf"
  local data_dir="$base_install_path/data"
  local custom_addons="$base_install_path/custom-addons"

  mkdir -p "$data_dir" "$custom_addons"

  local internal_addons="$odoo_clone_dir/odoo/addons"
  local external_addons="$odoo_clone_dir/addons"
  local addons_path="${internal_addons},${external_addons},${custom_addons}"

  cat > "$conf_file" <<EOCONF
[options]

# --- Paths ---
data_dir = $data_dir
addons_path = $addons_path

# This is the password that allows database operations:
admin_passwd = admin

# --- Connection Settings ---
http_port = $http_port
xmlrpc_port = $http_port
longpolling_port = $longpolling_port

# --- Database Connection (Requires PostgreSQL) ---
db_host = False
db_port = False
db_user = False
db_password = False
db_maxconn = 64

# --- Development & Logging ---
log_level = info
list_db = True
proxy_mode = False
debug_mode = False
without_demo = False
workers = 2
server_wide_modules = web
EOCONF

  log_success "  [OK] odoo.conf generated successfully at '$conf_file'."
}

clone_odoo_source() {
  local clone_dir="$1"

  log_step "Step 7 (final): Cloning Odoo $SELECTED_VERSION repository..."
  log_info " [INFO] Removing temporary files/folders to prepare for Git clone..."

  rm -rf "$clone_dir"

  local parent_dir
  parent_dir=$(dirname "$clone_dir")
  mkdir -p "$parent_dir"

  local git_command=(git clone --branch "$SELECTED_VERSION" --single-branch "$ODOO_REPO_URL" "$clone_dir")
  log_info "Executing: ${git_command[*]}"

  if ! "${git_command[@]}"; then
    log_error "Failed to clone Odoo repository (branch $SELECTED_VERSION)."
    exit 1
  fi

  log_success " [OK] Odoo $SELECTED_VERSION cloned successfully to '$clone_dir'."
}

install_dependencies() {
  local clone_dir="$1"
  local venv_python="$2"

  log_step "Step 5: Installing dependencies from requirements.txt..."

  if (cd "$clone_dir" && UV_PYTHON="$venv_python" uv pip install -r requirements.txt); then
    log_success " [OK] Dependencies installed successfully."
    return 0
  fi

  log_warn "Warning: initial dependency installation failed. Attempting libsass fallback..."

  local libsass_spec=""
  if [[ -f "$clone_dir/requirements.txt" ]]; then
    libsass_spec=$(grep -Ei '^libsass[[:space:]]*(==|>=|<=|~=).*$' "$clone_dir/requirements.txt" | head -n1 | tr -d '\r')
  fi

  if [[ -z "$libsass_spec" ]]; then
    libsass_spec="libsass"
  fi

  log_info "Attempting to install '$libsass_spec' without build isolation..."
  if ! (cd "$clone_dir" && UV_PYTHON="$venv_python" uv pip install --no-deps --no-build-isolation "$libsass_spec"); then
    log_error "Failed to install fallback package '$libsass_spec'."
    return 1
  fi

  log_success " [OK] Fallback package '$libsass_spec' installed successfully."

  log_warn "Re-running dependency installation for remaining packages..."
  if ! (cd "$clone_dir" && PYTHONIOENCODING='utf-8' UV_PYTHON="$venv_python" uv pip install -r requirements.txt --upgrade); then
    log_error "Remaining dependencies failed to install after libsass fix."
    return 1
  fi

  log_success " [OK] All dependencies installed successfully via manual intervention."
  return 0
}

main() {
  local original_dir
  original_dir=$(pwd)
  trap 'cd "$original_dir"' EXIT

  check_prerequisites
  select_odoo_version

  local major="${SELECTED_VERSION%%.*}"
  local parent_install_dir="$original_dir/odoo-$major"
  local clone_dir="$parent_install_dir/odoo-src"

  log_info "Setting up directory structure in '$parent_install_dir'..."
  mkdir -p "$parent_install_dir"
  rm -rf "$clone_dir"

  download_requirements_only "$clone_dir"
  prepare_psycopg_fallback "$clone_dir"
  prepare_reportlab_fallback "$clone_dir"
  prepare_gevent_cython_fallback "$clone_dir"

  log_step "Step 4: Setting up Python environment..."
  if ! (cd "$parent_install_dir" && uv venv --python "$REQUIRED_PYTHON_VERSION"); then
    log_error "Failed to create Python virtual environment. Ensure Python $REQUIRED_PYTHON_VERSION is available via 'uv'."
    exit 1
  fi
  log_success " [OK] Python virtual environment created with Python $REQUIRED_PYTHON_VERSION."

  local venv_python="$parent_install_dir/.venv/bin/python"

  log_step "Step 4.5: Installing 'setuptools' (required by Odoo runtime)..."
  if ! (UV_PYTHON="$venv_python" uv pip install setuptools); then
    log_error "Failed to install setuptools. Cannot continue."
    exit 1
  fi
  log_success " [OK] 'setuptools' installed."

  if ! install_dependencies "$clone_dir" "$venv_python"; then
    exit 1
  fi

  generate_odoo_conf "$parent_install_dir" "$clone_dir"

  clone_odoo_source "$clone_dir"

  local http_port="80${major}"
  styled_echo "$COLOR_MAGENTA" "------------------- Odoo Setup Complete -------------------"
  styled_echo "$COLOR_WHITE" " Installation Directory: $parent_install_dir"
  styled_echo "$COLOR_WHITE" " Odoo Version:          $SELECTED_VERSION"
  styled_echo "$COLOR_WHITE" " Odoo Source Path:      $clone_dir"
  styled_echo "$COLOR_WHITE" " Custom Addons Path:    $parent_install_dir/custom-addons"
  styled_echo "$COLOR_WHITE" " Config File:           $parent_install_dir/odoo.conf"
  styled_echo "$COLOR_WHITE" " HTTP Port:             $http_port (Longpolling: 8072)"
  styled_echo "$COLOR_MAGENTA" "-----------------------------------------------------------"
  styled_echo "$COLOR_YELLOW" "To start Odoo, run the following commands:"
  styled_echo "$COLOR_WHITE" " 1. cd \"$parent_install_dir\""
  styled_echo "$COLOR_WHITE" " 2. source .venv/bin/activate"
  styled_echo "$COLOR_WHITE" " 3. python odoo-src/odoo-bin -c odoo.conf"
  styled_echo "$COLOR_YELLOW" "Or run the shortcut command:"
  styled_echo "$COLOR_YELLOW" "  $parent_install_dir/.venv/bin/python $clone_dir/odoo-bin -c odoo.conf"
  styled_echo "$COLOR_RED" "Reminder: configure your PostgreSQL database before starting Odoo."
}

main "$@"
