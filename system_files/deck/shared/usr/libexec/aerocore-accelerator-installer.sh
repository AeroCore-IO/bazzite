#!/usr/bin/env bash
set -euo pipefail

: "${DECKY_MIRROR_HOST:=}"
: "${DECKY_PLUGIN_MIRROR_HOST:=${DECKY_MIRROR_HOST}}"
: "${DECKY_PLUGIN_TARGET_ID:=}"
: "${DECKY_PLUGIN_NAME:=aerocore-accelerator}"
: "${RESTART_GAME_MODE_AFTER_INSTALL:=1}"

: "${TMP_INSTALLER:=}"
: "${TMP_DECKY_CLIENT:=}"
: "${TMP_DECKY_CLIENT_CHECKSUM:=}"

cleanup() {
  rm -f "${TMP_INSTALLER:-}" "${TMP_DECKY_CLIENT:-}" "${TMP_DECKY_CLIENT_CHECKSUM:-}"
}

validate_config() {
  local value name

  for name in DECKY_MIRROR_HOST DECKY_PLUGIN_MIRROR_HOST DECKY_PLUGIN_TARGET_ID; do
    value="${!name:-}"
    if [[ -z "${value}" ]]; then
      echo "Required Decky install setting ${name} was not provided via environment configuration." >&2
      return 1
    fi
  done
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This command must be run as root." >&2
    return 1
  fi
}

require_non_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "This command must be run as the target user, not root." >&2
    return 1
  fi
}

get_active_uid() {
  local sid uid active state type seat

  while read -r sid uid; do
    active=$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)
    state=$(loginctl show-session "$sid" -p State --value 2>/dev/null || true)
    type=$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)
    seat=$(loginctl show-session "$sid" -p Seat --value 2>/dev/null || true)

    if [[ "$active" == "yes" || "$state" =~ ^(active|online)$ ]]; then
      printf '%s' "$uid"
      return 0
    fi

    if [[ "$seat" == "seat0" && "$type" =~ ^(x11|wayland|tty)$ && "$state" =~ ^(active|online)$ ]]; then
      printf '%s' "$uid"
      return 0
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

wait_for_target_session() {
  local wait_secs="${INSTALL_WAIT_SECS:-180}"
  local end=$((SECONDS + wait_secs))

  while (( SECONDS < end )); do
    TARGET_UID="$(get_active_uid || printf '')"
    if session_ready; then
      return 0
    fi
    sleep 1
  done

  echo "No active user session found after ${wait_secs}s." >&2
  return 1
}

run_as_target_user() {
  sudo -u "$TARGET_USER" env \
    HOME="$HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    SUDO_USER="$TARGET_USER" \
    TARGET_UID="$TARGET_UID" \
    TARGET_USER="$TARGET_USER" \
    XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
    DECKY_MIRROR_HOST="$DECKY_MIRROR_HOST" \
    DECKY_PLUGIN_MIRROR_HOST="$DECKY_PLUGIN_MIRROR_HOST" \
    DECKY_PLUGIN_TARGET_ID="$DECKY_PLUGIN_TARGET_ID" \
    DECKY_PLUGIN_NAME="$DECKY_PLUGIN_NAME" \
    TMP_DECKY_CLIENT="$TMP_DECKY_CLIENT" \
    "$@"
}

invoke_accelerator_install_as_target_user() {
  run_as_target_user bash "$0" install-accelerator
}

ensure_home_deck_symlink() {
  if [[ ! -L /home/deck && ! -e /home/deck && "$HOME" != "/home/deck" ]]; then
    echo "Making a /home/deck symlink to fix plugins that do not use environment variables."
    ln -sf "$HOME" /home/deck
  fi
}

install_decky_loader() {
  local skip_decky_install=false
  local target_homebrew_dir

  ensure_home_deck_symlink

  echo "Checking if Decky Loader is already installed and running..."
  if systemctl is-active --quiet plugin_loader.service 2>/dev/null; then
    echo "Decky Loader (plugin_loader.service) is already running. Skipping Decky Loader installation."
    skip_decky_install=true
  else
    echo "Decky Loader is not running or not installed. Proceeding with installation."
  fi

  if [[ "$skip_decky_install" == true ]]; then
    return 0
  fi

  TMP_INSTALLER="$(mktemp /tmp/decky_user_install_script.XXXXXX.sh)"
  if ! curl -fsSL "https://${DECKY_MIRROR_HOST}/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh" \
    | sed -E \
      -e "s#github\.com#${DECKY_MIRROR_HOST}#g" \
      -e "s#api\.github\.com#api.${DECKY_MIRROR_HOST}#g" \
      -e "s#raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/#${DECKY_MIRROR_HOST}/\\1/\\2/plain/#g" \
      > "${TMP_INSTALLER}"; then
    echo "Failed to download or rewrite the official installer script." >&2
    return 1
  fi

  set +e
  bash "${TMP_INSTALLER}"
  local installer_status=$?
  set -e

  target_homebrew_dir="${HOME}/homebrew"
  if [[ -d "${target_homebrew_dir}" ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "${target_homebrew_dir}"
  fi

  if [[ -d "${target_homebrew_dir}/services/PluginLoader" ]]; then
    chcon -R -t bin_t "${target_homebrew_dir}/services/PluginLoader" || true
  fi

  if systemctl is-active --quiet plugin_loader.service 2>/dev/null; then
    echo "Decky Loader install completed (installer exit code: ${installer_status})."
    return 0
  fi

  echo "Decky Loader install did not complete successfully (installer exit code: ${installer_status})." >&2
  return 1
}

download_decky_client() {
  TMP_DECKY_CLIENT="$(mktemp /tmp/decky_client.XXXXXX.py)"
  TMP_DECKY_CLIENT_CHECKSUM="$(mktemp /tmp/decky_client.XXXXXX.sha256)"

  if ! curl -fsSL "https://${DECKY_MIRROR_HOST}/AeroCore-IO/decky-installer/releases/latest/download/decky_client.py" \
    -o "${TMP_DECKY_CLIENT}"; then
    echo "Failed to download Decky Loader client script." >&2
    return 1
  fi
  chmod 0644 "${TMP_DECKY_CLIENT}"

  if ! curl -fsSL "https://${DECKY_MIRROR_HOST}/AeroCore-IO/decky-installer/releases/latest/download/decky_client.py.sha256" \
    -o "${TMP_DECKY_CLIENT_CHECKSUM}"; then
    echo "Failed to download checksum file for Decky Loader client." >&2
    return 1
  fi
  chmod 0644 "${TMP_DECKY_CLIENT_CHECKSUM}"

  if ! sha256sum "${TMP_DECKY_CLIENT}" | awk '{print $1}' | diff -q - <(awk '{print $1}' "${TMP_DECKY_CLIENT_CHECKSUM}") >/dev/null; then
    echo "Checksum verification failed for Decky Loader client. File may be compromised." >&2
    return 1
  fi
}

configure_store_and_install_plugin() {
  require_non_root

  local store_url="https://${DECKY_PLUGIN_MIRROR_HOST}/plugins"

  echo "Configuring Decky store URL to ${store_url}..."
  python3 "${TMP_DECKY_CLIENT}" configure-store "${store_url}"

  echo "Installing Decky plugin ${DECKY_PLUGIN_NAME} (target id: ${DECKY_PLUGIN_TARGET_ID})..."
  python3 "${TMP_DECKY_CLIENT}" install \
    --store-url "${store_url}" \
    --target-id "${DECKY_PLUGIN_TARGET_ID}"
}

restart_game_mode_session() {
  require_root

  if [[ "${RESTART_GAME_MODE_AFTER_INSTALL}" != "1" ]]; then
    return 0
  fi

  if ! pgrep -u "${TARGET_USER}" -x steam >/dev/null 2>&1; then
    echo "Steam is not running for ${TARGET_USER}. Skipping game mode restart."
    return 0
  fi

  echo "Requesting Steam restart so Decky UI changes become visible in game mode..."
  if ! run_as_target_user /usr/bin/steam -shutdown; then
    echo "Failed to request Steam shutdown after Decky install." >&2
    return 0
  fi

  local wait_secs=30
  local end=$((SECONDS + wait_secs))
  while (( SECONDS < end )); do
    if ! pgrep -u "${TARGET_USER}" -x steam >/dev/null 2>&1; then
      echo "Steam exited. Game mode should relaunch it automatically."
      return 0
    fi
    sleep 1
  done

  echo "Steam did not exit within ${wait_secs}s after shutdown request." >&2
  return 0
}

install_decky() {
  require_root
  trap cleanup EXIT

  wait_for_target_session

  : "${TARGET_UID:?TARGET_UID not resolved}"
  TARGET_USER="$(getent passwd "$TARGET_UID" | cut -d: -f1)"
  : "${TARGET_USER:?TARGET_USER not resolved}"

  export SUDO_USER="$TARGET_USER"
  export HOME="$(getent passwd "$TARGET_UID" | cut -d: -f6)"
  export DECKY_MIRROR_HOST
  export DECKY_PLUGIN_MIRROR_HOST
  export DECKY_PLUGIN_TARGET_ID
  export DECKY_PLUGIN_NAME

  validate_config
  install_decky_loader
  download_decky_client
  invoke_accelerator_install_as_target_user
  restart_game_mode_session
}

install_accelerator() {
  require_non_root

  validate_config
  : "${HOME:?HOME not set}"
  : "${TARGET_UID:?TARGET_UID not set}"
  : "${TARGET_USER:?TARGET_USER not set}"
  : "${TMP_DECKY_CLIENT:?TMP_DECKY_CLIENT not set}"

  configure_store_and_install_plugin
}

main() {
  local cmd="${1:-}"

  case "${cmd}" in
    install-accelerator)
      shift
      install_accelerator "$@"
      ;;
    "")
      install_decky
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      return 1
      ;;
  esac
}

main "$@"
