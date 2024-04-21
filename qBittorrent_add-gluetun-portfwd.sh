#!/bin/bash

#######################################################################################################################
##                                                                                                                   ##
## This script updates qBittorrents listening port to match the port forward managed by Gluetun.                     ##
## Gluetun's HTTP server is queried for the current port forward. qBittorrent is updated via changes made to to its  ##
## configuration file.                                                                                               ##
##                                                                                                                   ##
## NB: qBittorrent must not be running whilst executing this script.                                                 ##
##     Settings are read to memory from the configurtion file on start-up and written back to storage on shutdown.   ##
##     This script will have no effect if executed whilst qBittorrent it running.                                    ##
##                                                                                                                   ##
#######################################################################################################################

## CONFIGURATION

gluetun_http_server_endpoint="http://localhost:8000/v1/openvpn/portforwarded"
qbittorrent_configuration_file="/config/qBittorrent/qBittorrent.conf"


## FUNCTIONS

logger () {
    local type="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    local style_default="\e[m"
    local style="$style_default"
    case "$type" in
        E) style="\e[91m" ;;            # ERROR             # RED
        I) style="\e[96m" ;;            # INFORMATION       # CYAN
        N) style="\e[m" ;;              # NORMAL            # DEFAULT
        *) ;;
    esac
    printf "$style(%s) $style_default%s - $style_default%s\n" "$type" "$timestamp" "$message"
}

check_for () {
    local missing_packages=()
    for package in "$@"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
            logger E "Dependancy Error: $package is not installed."
        fi
    done
    if [ ${#missing_packages[@]} -gt 0 ]; then
        logger E "Aborting."
	    exit 1
    fi
}

get_gluetun_forwarded_port () {
    local gluetun_response=$(curl -s "$gluetun_http_server_endpoint")
    gluetun_forwarded_port=$(echo $gluetun_response | jq '.port')
}

get_qbittorrent_listening_port () {
    if [ -f "$qbittorrent_configuration_file" ]; then
        qbittorrent_listening_port=$(grep -Eo 'Session\\Port=[0-9]+' "$qbittorrent_configuration_file" | cut -d= -f2)
    else
        logger E "Configuration file not accessible at '$qbittorrent_configuration_file'"
    fi
}

update_qbittorrent_listening_port () {
    local new_port="$1"
    sed -i "s/Session\\\\Port=.*/Session\\\\Port=$new_port/g" "$qbittorrent_configuration_file"
}


## START

logger N "Checking port configuration..."

check_for curl jq grep cut sed

get_gluetun_forwarded_port
if [ -z "$gluetun_forwarded_port" ]; then
    logger E "Unable to retrieve forwarded port from Gluetun."
    logger E "Aborting."
    exit 1
fi

get_qbittorrent_listening_port
if [ -z "$qbittorrent_listening_port" ]; then
    logger E "Unable to retrieve listening port from qBittorrent."
    logger E "Aborting."
    exit 1
fi

if [ "$gluetun_forwarded_port" == "$qbittorrent_listening_port" ]; then
    logger I "Port configuration is OK!"
else
    update_qbittorrent_listening_port $gluetun_forwarded_port
    logger E "Port configuration is invalid."
    logger I "Listening port changed from $qbittorrent_listening_port to $gluetun_forwarded_port."
fi

