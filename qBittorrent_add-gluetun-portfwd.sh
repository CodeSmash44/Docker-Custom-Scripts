#!/bin/bash

#######################################################################################################################
##                                                                                                                   ##
## This script updates qBittorrents listening port to match the port forward managed by Gluetun.                     ##
## Gluetun's HTTP server is queried for the current port forward. qBittorrent is updated via changes made to to its  ##
## configuration file.                                                                                               ##
##                                                                                                                   ##
## NB:   qBittorrent must not be running whilst executing this script.                                               ##
##       Settings are read to memory from the configurtion file on start-up and written back to storage on shutdown. ##
##       This script will have no effect if executed whilst qBittorrent it running.                                  ##
##                                                                                                                   ##
#######################################################################################################################

## CONFIGURATION

#  GLUETUN
GLUETUN_URL="http://localhost:8000"
GLUETUN_USE_AUTH=true
GLUETUN_API_KEY="api_key"
GLUETUN_USERNAME="username"
GLUETUN_PASSWORD="password"
    # API_KEY is the default if provided (leave blank if using USERNAME:PASSWORD)
    # see 'https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md'
    # to configure gluetun auth

# GLUETUN API ENDPOINT
GLUETUN_API_ENDPOINT="${GLUETUN_URL}/v1/openvpn/portforwarded"

# QBITTORRENT CONFIGURATION FILE
QBIT_CONFIG_FILE_PATH="/config/qBittorrent/qBittorrent.conf"

## FUNCTIONS

logger () {
    local type="$1"
    local message="$2"
    local timestamp
    local style_default="\e[m"
    local style="$style_default"

    timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    case "$type" in
        E) style="\e[91m" ;;            # ERROR             # RED
        I) style="\e[96m" ;;            # INFORMATION       # CYAN
        N) style="\e[m" ;;              # NORMAL            # DEFAULT
        *) ;;
    esac
    printf "$style(%s) $style_default%s - $style_default%s\n" "$type" "$timestamp" "$message"
}

check_for() {
    local missing_packages=()

    for package in "$@"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
            logger E "Dependancy Error: $package is not installed."
        fi
    done
    if [ ${#missing_packages[@]} -gt 0 ]; then
        logger E "Exiting."
        exit 1
    fi
}

get_gluetun_forwarded_port() {
    local gluetun_response

    if [ "$GLUETUN_USE_AUTH" == true ]; then
        if [ -n "$GLUETUN_API_KEY" ]; then
            gluetun_response=$(curl --silent --fail --show-error \
                --header "X-API-Key: $GLUETUN_API_KEY" \
                --request GET "$GLUETUN_API_ENDPOINT")
        else
            gluetun_response=$(curl --silent --fail --show-error \
                --user ${GLUETUN_USERNAME}:${GLUETUN_PASSWORD} \
                --request GET "$GLUETUN_API_ENDPOINT")
        fi
    else
        gluetun_response=$(curl --silent --fail --show-error \
            --request GET "$GLUETUN_API_ENDPOINT")
    fi
    if [ "$gluetun_response" == "Unauthorized" ]; then
        logger E "Unable to authenticate with Gluetun. Endpoint: '$GLUETUN_API_ENDPOINT'"
    else
        gluetun_forwarded_port=$(echo "$gluetun_response" | jq -r '.port' 2>/dev/null)
    fi
}

get_qbittorrent_listening_port() {
    if [ -f "$QBIT_CONFIG_FILE_PATH" ]; then
        qbittorrent_listening_port=$(grep -Eo 'Session\\Port=[0-9]+' "$QBIT_CONFIG_FILE_PATH" | cut -d= -f2)
    else
        logger E "Configuration file not accessible at: '$QBIT_CONFIG_FILE_PATH'"
    fi
}

update_qbittorrent_listening_port() {
    local new_port="$1"

    sed -i "s/Session\\\\Port=.*/Session\\\\Port=$new_port/g" "$QBIT_CONFIG_FILE_PATH"
}

## START

logger N "Checking qBittorrent port configuration..."

check_for curl jq grep cut sed

get_gluetun_forwarded_port
if [ -z "$gluetun_forwarded_port" ]; then
    logger E "Unable to retrieve forwarded port from Gluetun. Exiting."
    exit 1
fi

get_qbittorrent_listening_port
if [ -z "$qbittorrent_listening_port" ]; then
    logger E "Unable to retrieve listening port from qBittorrent. Exiting."
    exit 1
fi

if [ "$gluetun_forwarded_port" == "$qbittorrent_listening_port" ]; then
    logger I "Port configuration is OK!"
else
    logger E "Port configuration is broken."
    update_qbittorrent_listening_port "$gluetun_forwarded_port"
    logger I "Listening port changed from $qbittorrent_listening_port to $gluetun_forwarded_port."
fi
