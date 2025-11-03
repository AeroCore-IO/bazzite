#!/usr/bin/env bash
if [[ -r /etc/bazzite-decky-mirror.conf ]]; then
  source /etc/bazzite-decky-mirror.conf
fi

: "${MIRROR_HOST:=https://github.com}"
: "${API_MIRROR_HOST:=https://api.github.com}"

__real_curl() {
  command curl "$@"
}

__is_url() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
}

__rewrite_url() {
  local url="$1"
  if [[ "$url" == https://api.github.com/* ]]; then
    printf '%s\n' "${url/https:\/\/api.github.com/${API_MIRROR_HOST}}"
  elif [[ "$url" == https://github.com/* ]]; then
    printf '%s\n' "${url/https:\/\/github.com/${MIRROR_HOST}}"
  else
    printf '%s\n' "$url"
  fi
}

curl() {
  local args=()
  local url=""
  local saw_url=0

  for a in "$@"; do
    if [[ $saw_url -eq 0 ]] && __is_url "$a"; then
      saw_url=1
      url="$a"
    else
      args+=("$a")
    fi
  done

  # if no url found, passthrough
  if [[ -z "$url" ]]; then
    __real_curl "$@"
    return $?
  fi

  local new_url
  new_url="$(__rewrite_url "$url")"

  local need_passthrough=false

  # passthrough if certain options are present
  for a in "$@"; do
    case "$a" in
      -X|--request|-o|--output|-O)
        need_passthrough=true
        break
        ;;
    esac
  done

  if $need_passthrough; then
    __real_curl "${args[@]}" "$new_url"
    return $?
  fi

  __real_curl "${args[@]}" "$new_url" \
    | sed \
      -e "s|https://api.github.com/|${API_MIRROR_HOST}/|g" \
      -e "s|https://github.com/|${MIRROR_HOST}/|g"
}
