#!/usr/bin/env bash

### COMMON PART

RED='\033[0;31m'
RED_BOLD='\033[1;31m'
GREEN='\033[0;32m'
GREEN_BOLD='\033[1;32m'
YELLOW='\033[0;33m'
YELLOW_BOLD='\033[1;33m'
BLUE='\033[0;34m'
BLUE_BOLD='\033[1;34m'
WHITE='\033[0;37m'
WHITE_BOLD='\033[1;37m'
NOCOLOR='\033[0m'

fatal() {
    >&2 printf "$( date '+[%F %T]' ) ${RED_BOLD}ERROR${NOCOLOR} ${RED}${1}${NOCOLOR}\n"
    exit 1
}

err() {
    >&2 printf "$( date '+[%F %T]' ) ${RED_BOLD}ERROR${NOCOLOR} ${RED}${1}${NOCOLOR}\n"
}

warn() {
    >&2 printf "$( date '+[%F %T]' ) ${YELLOW_BOLD}WARNING${NOCOLOR} ${YELLOW}${1}${NOCOLOR}\n"
}

info() {
    >&2 printf "$( date '+[%F %T]' ) ${GREEN_BOLD}INFO${NOCOLOR} ${BLUE}${1}${NOCOLOR}\n"
}

### MAIN PART

set -u
set -o pipefail

command -v jq &> /dev/null || fatal "jq not installed."
command -v nc &> /dev/null || fatal "netcat not installed."
command -v curl &> /dev/null || fatal "curl not installed."

JSON_PATH="../proxies/all/data.json"
TEST_URL=${1:-"https://youtube.com"}
CONNECT_TIMEOUT=5
MAX_TIME=12

jq -r '
  .[] |
  [
    .proxy,
    .protocol,
    .ip,
    (.port | tostring)
  ] | @tsv
' "$JSON_PATH" |
while IFS=$'\t' read -r proxy protocol ip port; do
  printf 'proxy=%s\n' "$proxy"

  if nc -z -w "$CONNECT_TIMEOUT" "$ip" "$port" >/dev/null 2>&1; then
    info "port_check=OPEN"
  else
    err "port_check=CLOSED"
    echo "test_check=SKIPPED"
    echo
    continue
  fi

  case "$protocol" in
    http)
      curl_proxy="http://$ip:$port"
      ;;
    https)
      curl_proxy="https://$ip:$port"
      ;;
    socks4)
      curl_proxy="socks4a://$ip:$port"
      ;;
    socks5)
      curl_proxy="socks5h://$ip:$port"
      ;;
    *)
      echo "test_check=UNSUPPORTED_PROTOCOL($protocol)"
      echo
      continue
      ;;
  esac

  http_code="$(
    curl \
      --proxy "$curl_proxy" \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      --location \
      --silent \
      --show-error \
      --output /dev/null \
      --write-out '%{http_code}' \
      "$TEST_URL" 2>/dev/null
  )"

  curl_rc=$?

  if [ "$curl_rc" -eq 0 ]; then
    info "test_check=OK http_code=$http_code via=$curl_proxy"
    echo
    printf "${GREEN_BOLD}Success!${NOCOLOR}\n"
    echo
    printf "${WHITE_BOLD}Use this proxy:${NOCOLOR} ${BLUE_BOLD}${curl_proxy}${NOCOLOR}\n"
    echo
    exit 0
  else
    err "test_check=FAIL curl_exit=$curl_rc via=$curl_proxy"
  fi

  echo
done
