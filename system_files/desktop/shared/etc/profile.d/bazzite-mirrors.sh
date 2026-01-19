#!/usr/bin/bash

load_mirror_file() {
    local file="$1"
    [[ -r "$file" ]] || return

    while IFS='=' read -r key value; do
        [[ -z "$key" || "${key:0:1}" == "#" ]] && continue
        case "$key" in
            FLATPAK_REMOTE_URL|HOMEBREW_BOTTLE_DOMAIN)
                [[ -n "$value" ]] && export "$key"="$value"
                ;;
        esac
    done <"$file"
}

load_mirror_file /etc/bazzite/mirrors
load_mirror_file "$HOME/mirrors"
