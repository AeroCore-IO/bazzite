#!/usr/bin/env bash
set -euo pipefail

: "${DECKY_MIRROR_HOST:=decky.mirror.aerocore.com.cn}"

get_active_uid() {
  local sid uid active state type seat

  while read -r sid uid; do
    active=$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)
    state=$(loginctl show-session "$sid" -p State   --value 2>/dev/null || true)
    type=$(loginctl show-session "$sid" -p Type     --value 2>/dev/null || true)
    seat=$(loginctl show-session "$sid" -p Seat     --value 2>/dev/null || true)

    if [[ "$active" == "yes" || "$state" =~ ^(active|online)$ ]]; then
      printf '%s' "$uid"; return 0
    fi

    if [[ "$seat" == "seat0" &&
          "$type" =~ ^(x11|wayland|tty)$ &&
          "$state" =~ ^(active|online)$ ]]; then
      printf '%s' "$uid"; return 0
    fi
  done < <(loginctl list-sessions --no-legend | awk '{print $1, $2}')

  return 1
}

session_ready() {
  [[ -n "${TARGET_UID:-}" ]] || return 1

  READY_XDG_RUNTIME_DIR="/run/user/${TARGET_UID}"

  [[ -d "${READY_XDG_RUNTIME_DIR:-}" ]] || return 1
  [[ -S "${READY_XDG_RUNTIME_DIR}/bus" ]] || return 1

  local target_user steampid_path steampid

  target_user=$(getent passwd "$TARGET_UID" | cut -d: -f1)
  steampid_path="/home/${target_user}/.steampid"

  [[ -f "${steampid_path}" ]] || return 1

  steampid=$(<"${steampid_path}")
  pgrep -u "${target_user}" -x steam | grep -q "^${steampid}$"
}

# Wait for an active user session and its runtime dir
wait_secs="${INSTALL_WAIT_SECS:-180}"
end=$((SECONDS + wait_secs))

while (( SECONDS < end )); do
  TARGET_UID="$(get_active_uid || printf '')"
  if session_ready; then
    break
  fi
  sleep 1
done

: "${TARGET_UID:?No active user session found after ${wait_secs}s}"
TARGET_USER="$(getent passwd "$TARGET_UID" | cut -d: -f1)"
: "${TARGET_USER:?TARGET_USER not resolved}"

export SUDO_USER="$TARGET_USER"
export HOME="$(getent passwd "$TARGET_UID" | cut -d: -f6)"
export DECKY_MIRROR_HOST

install_plugin() {
    local repo_owner="$1"
    local repo_name="$2" 
    local plugin_name="$3"
    local filename="$4"
    local plugin_dir="$HOME/homebrew/plugins"

    echo "Installing $plugin_name..."

    # Check if Decky is installed
    if [ ! -d "$HOME/homebrew" ]; then
        echo "Error: Decky Loader is not installed. Please run 'ujust setup-decky install' first." >&2;
        return 1
    fi

    # Get the latest release information with timeout
    echo "Fetching latest release information for $plugin_name..."
    local release_info
    release_info=$(timeout 30 curl -s "https://api.$DECKY_MIRROR_HOST/repos/$repo_owner/$repo_name/releases/latest" || echo "")

    # Check if the specified filename exists in the release
    local download_url=""
    if [ -n "$release_info" ]; then
        download_url=$(echo "$release_info" | jq -r --arg filename "$filename" '.assets[] | select(.name == $filename) | .browser_download_url' 2>/dev/null || echo "")
    fi

    # Determine plugin URL
    local plugin_url
    if [ -z "$download_url" ]; then
        echo "Specified file '$filename' not found in latest release or API timeout. Using direct URL..."
        plugin_url="https://$DECKY_MIRROR_HOST/$repo_owner/$repo_name/releases/latest/download/$filename"
    else
        plugin_url="$download_url"
        echo "Found specified file in release: $plugin_url"
    fi

    # Ensure plugins directory exists
    if [ ! -d "$plugin_dir" ]; then
        echo "Creating plugins directory..."
        mkdir -p "$plugin_dir"
    fi

    # Work in a temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || { echo "Failed to create temp directory"; return 1; }

    # Remove any existing plugin folder
    if [ -d "$plugin_dir/$plugin_name" ]; then
        echo "Removing existing $plugin_name directory..."
        rm -rf "$plugin_dir/$plugin_name"
    fi

    # Download the plugin file
    echo "Downloading $plugin_name from $plugin_url..."
    local temp_file="plugin_file"
    if ! timeout 60 curl -L -o "$temp_file" "$plugin_url"; then
        echo "Download failed or timed out!"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract plugin based on file type
    echo "Extracting $plugin_name..."
    if [[ "$plugin_url" == *.tar.gz ]]; then
        if ! tar -xzf "$temp_file"; then
            echo "Extraction failed!"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 1
        fi
    elif [[ "$plugin_url" == *.zip ]]; then
        if ! unzip -o "$temp_file" -d .; then
            echo "Extraction failed!"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 1
        fi
    else
        echo "Unsupported file type. Only .zip and .tar.gz are supported."
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    # Handle different extracted folder names
    local extracted_folders
    extracted_folders=$(find . -maxdepth 1 -type d -not -name "." | head -n 1)

    if [ -n "$extracted_folders" ] && [ "$extracted_folders" != "./$plugin_name" ]; then
        echo "Found plugin folder: $extracted_folders"
        echo "Renaming to $plugin_name..."
        mv "$extracted_folders" "./$plugin_name"
    fi

    # Handle nested folder structure if needed
    if [ -d "./$plugin_name/$plugin_name" ]; then
        echo "Fixing nested folder structure..."
        mv "./$plugin_name/$plugin_name/"* "./$plugin_name/" 2>/dev/null || true
        rm -rf "./$plugin_name/$plugin_name"
    fi

    # Move plugin to final location
    if [ -d "./$plugin_name" ]; then
        echo "Installing $plugin_name to $plugin_dir..."
        mv "./$plugin_name" "$plugin_dir/"

        # Fix permissions
        echo "Setting correct permissions..."
        find "$plugin_dir/$plugin_name" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        find "$plugin_dir/$plugin_name" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true

        echo "$plugin_name has been installed successfully!"
    else
        echo "Installation failed. Plugin folder could not be found."
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    # Clean up
    cd $HOME > /dev/null
    rm -rf "$temp_dir"
    return 0
}

install_decky_loader() {
  if [[ ! -f /etc/systemd/system/multi-user.target.wants/plugin_loader.service ]]; then
    if [ ! -L "/home/deck" ] && [ ! -e "/home/deck" ]  && [ "$HOME" != "/home/deck" ]; then
      echo "Making a /home/deck symlink to fix plugins that do not use environment variables."
      ln -sf "$HOME" /home/deck
    fi

    echo "Downloading and installing Decky Loader PluginLoader service..."
    curl -sL https://${DECKY_MIRROR_HOST}/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh | sed -E \
      -e "s#github\.com#${DECKY_MIRROR_HOST}#g" \
      -e "s#raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/#${DECKY_MIRROR_HOST}/\1/\2/plain/#g" | sh

    if [ -d "$HOME/homebrew/services/PluginLoader" ]; then
      chcon -R -t bin_t $HOME/homebrew/services/PluginLoader
    fi
  fi
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd:-}" in
    install_plugin) install_plugin "$@";;
    ""|help|-h|--help) usage;;
    *) echo "Unknown command: $cmd" >&2; usage;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" && $# -gt 0 ]]; then
  main "$@"
else
  install_decky_loader
  systemctl stop plugin_loader.service
  chown -R $SUDO_USER:$SUDO_USER $HOME/homebrew/plugins
  sudo -u $SUDO_USER bash "$0" install_plugin "aerocore-io" "decky-accelerator" "aerocore-accelerator" "aerocore-accelerator.zip"
  systemctl start plugin_loader.service
fi

