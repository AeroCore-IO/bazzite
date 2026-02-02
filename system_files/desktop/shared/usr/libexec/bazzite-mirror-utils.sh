#!/usr/bin/bash

is_valid_mirror_url() {
  local value="$1"
  [[ "$value" =~ ^https?://[^[:space:]]+$ ]]
}

update_flathub_repo_url() {
  local raw_url="$1"
  local repo_file="/etc/flatpak/remotes.d/flathub.flatpakrepo"
  local tmp_file="/tmp/flathub.flatpakrepo"

  [[ -z "$raw_url" ]] && return 1
  local url="${raw_url%/}/"

  awk -v url="$url" 'BEGIN{updated=0} /^Url=/ {print "Url=" url; updated=1; next} {print} END{if(!updated) print "Url=" url}' "$repo_file" > "$tmp_file" && \
    mv "$tmp_file" "$repo_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "$1" in
    update_flathub_repo_url)
      shift
      update_flathub_repo_url "$@"
      ;;
  esac
fi
