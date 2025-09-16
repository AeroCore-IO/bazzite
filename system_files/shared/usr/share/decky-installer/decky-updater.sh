#!/bin/sh

#If $1 is set, take that as input
[ -n "$DECKY_INSTALL_MODE" ] && release="$DECKY_INSTALL_MODE"
[ -n "$1" ] && release="$1"

if [ "$UID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    if [ -n "$DECKY_INSTALL_USER" ]; then
        SUDO_USER="$DECKY_INSTALL_USER"
    else
        SUDO_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
    fi

    if [ -z "$SUDO_USER" ]; then
        echo "Unable to determine target user for Decky installation."
        exit 1
    fi

    export SUDO_USER
fi

mark_success() {
    [ -n "$DECKY_INSTALL_MARKER_PATH" ] || return 0
    mkdir -p "$(dirname "$DECKY_INSTALL_MARKER_PATH")"
    touch "$DECKY_INSTALL_MARKER_PATH"
}

clear_marker() {
    [ -n "$DECKY_INSTALL_MARKER_PATH" ] || return 0
    rm -f "$DECKY_INSTALL_MARKER_PATH"
}

#Keep asking which release to install
while true
do
    #If $release is set by $1, take that as input
    [ -z "$release" ] && read -p "Install stable/pre-release or uninstall (s/p/u): " release

    #Only accept answers with S for stable or P for pre-release
    case $(echo "${release}" | tr '[:lower:]' '[:upper:]') in
    S*)
        echo "Installing stable version"
        if curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh | sh; then
            mark_success
            exit 0
        else
            exit $?
        fi
        ;;
    P*)
        echo "Installing pre-release"
        if curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_prerelease.sh | sh; then
            mark_success
            exit 0
        else
            exit $?
        fi
        ;;
    U*)
        echo "Uninstalling decky"
        if curl -L https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/uninstall.sh | sh; then
            clear_marker
            exit 0
        else
            exit $?
        fi
        ;;
    *)
        unset release
        continue
        ;;
    esac
done
