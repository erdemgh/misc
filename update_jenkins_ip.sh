#!/bin/bash

# === CONFIG ===
JENKINS_SERVICE="jenkins"
JENKINS_CONFIG="/var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml"
EXPECTED_STATE="active"

# === FUNCTIONS ===

get_eth0_ip() {
    ip -br -4 address show dev eth0 | awk '{print $3}' | cut -d '/' -f1
}

get_config_ip() {
    grep -oP '(?<=<jenkinsUrl>http://)[^:/]+' "$JENKINS_CONFIG"
}

get_config_port() {
    grep -oP '(?<=<jenkinsUrl>)[^<]+' "$JENKINS_CONFIG" | awk -F: '{print $3}' | cut -d '/' -f1
}

is_jenkins_running() {
    systemctl is-active --quiet "$JENKINS_SERVICE"
}

stop_jenkins() {
    echo "[INFO] Stopping Jenkins..."
    sudo systemctl stop "$JENKINS_SERVICE"
}

start_jenkins() {
    echo "[INFO] Starting Jenkins..."
    sudo systemctl start "$JENKINS_SERVICE"
}

backup_config() {
    local timestamp
    timestamp=$(TZ="Europe/Istanbul" date +'%Y-%m-%d_%H-%M-%S')
    local backup_file="${JENKINS_CONFIG}_${timestamp}.bak"
    echo "[INFO] Backing up config to: $backup_file"
    sudo cp "$JENKINS_CONFIG" "$backup_file"
}

replace_config_ip() {
    local old_ip="$1"
    local new_ip="$2"
    echo "[INFO] Replacing IP: $old_ip -> $new_ip in config."

    # URL kısmını escape edelim
    local escaped_old_url
    local escaped_new_url
    escaped_old_url=$(printf '%s' "http://$old_ip" | sed 's/[&/\]/\\&/g')
    escaped_new_url=$(printf '%s' "http://$new_ip" | sed 's/[&/\]/\\&/g')

    sudo sed -i "s|$escaped_old_url|$escaped_new_url|g" "$JENKINS_CONFIG"
}

verify_ip_replacement() {
    local current_ip
    current_ip=$(get_config_ip)
    if [[ "$current_ip" == "$1" ]]; then
        echo "[INFO] IP replacement successful."
    else
        echo "[ERROR] IP replacement failed. Current config IP: $current_ip"
        exit 1
    fi
}

check_config_url_tag() {
    echo "[INFO] Checking <jenkinsUrl> tag structure..."

    local open_tags
    local close_tags

    open_tags=$(grep -c "<jenkinsUrl>" "$JENKINS_CONFIG")
    close_tags=$(grep -c "</jenkinsUrl>" "$JENKINS_CONFIG")

    if [[ "$open_tags" -eq 1 && "$close_tags" -eq 1 ]]; then
        echo "[INFO] <jenkinsUrl> tag structure looks OK."
    else
        echo "[ERROR] <jenkinsUrl> tag malformed or appears multiple times."
        exit 1
    fi
}

check_jenkins_status() {
    local status
    status=$(systemctl is-active "$JENKINS_SERVICE")
    echo "[INFO] Jenkins service status: $status"
    if [[ "$status" == "$EXPECTED_STATE" ]]; then
        local config_ip config_port
        config_ip=$(get_config_ip)
        config_port=$(get_config_port)
        echo "[INFO] Jenkins is active. Access it at: http://$config_ip:$config_port"
    else
        echo "[ERROR] Jenkins is not in expected state: $EXPECTED_STATE"
        exit 1
    fi
}

main() {
    local eth0_ip config_ip config_port
    eth0_ip=$(get_eth0_ip)
    config_ip=$(get_config_ip)
    config_port=$(get_config_port)

    echo "[INFO] eth0 IP Address: $eth0_ip"
    echo "[INFO] Jenkins Config IP: $config_ip"
    echo "[INFO] Jenkins Config Port: $config_port"

    if [[ "$eth0_ip" != "$config_ip" ]]; then
        echo "[WARN] IP mismatch detected."

        if is_jenkins_running; then
            stop_jenkins
        fi

        backup_config
        replace_config_ip "$config_ip" "$eth0_ip"
        verify_ip_replacement "$eth0_ip"
        check_config_url_tag
        start_jenkins
        sleep 5
        check_jenkins_status
    else
        echo "[INFO] No IP mismatch. No update needed."
        echo "[INFO] Jenkins is accessible at: http://$config_ip:$config_port"
    fi
}

main "$@"