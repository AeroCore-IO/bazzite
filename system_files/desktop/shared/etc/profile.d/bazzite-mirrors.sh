#!/usr/bin/bash

[[ -r /usr/libexec/bazzite-mirror-utils.sh ]] && source /usr/libexec/bazzite-mirror-utils.sh

load_mirror_file() {
    local file="$1"
    [[ -r "$file" ]] || return

    while IFS='=' read -r key value; do
        [[ -z "$key" || "${key:0:1}" == "#" ]] && continue
        case "$key" in
            FLATPAK_REMOTE_URL|HOMEBREW_BOTTLE_DOMAIN)
                if is_valid_mirror_url "$value"; then
                    export "$key"="$value"
                fi
                ;;
        esac
    done <"$file"
}

load_mirror_file /etc/bazzite/mirrors
load_mirror_file "$HOME/mirrors"
