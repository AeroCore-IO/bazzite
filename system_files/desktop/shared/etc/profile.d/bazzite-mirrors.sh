#!/usr/bin/bash

is_valid_mirror_value() {
    local value="$1"
    [[ "$value" =~ ^https?://[^[:space:]]+$ ]]
}

load_mirror_file() {
    local file="$1"
    [[ -r "$file" ]] || return

    while IFS='=' read -r key value; do
        [[ -z "$key" || "${key:0:1}" == "#" ]] && continue
        case "$key" in
            FLATPAK_REMOTE_URL|HOMEBREW_BOTTLE_DOMAIN)
                if is_valid_mirror_value "$value"; then
                    export "$key"="$value"
                fi
                ;;
        esac
    done <"$file"
}

load_mirror_file /etc/bazzite/mirrors
load_mirror_file "$HOME/mirrors"
