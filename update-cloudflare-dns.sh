#!/usr/bin/env bash

###  Create .update-cloudflare-dns.log file of the last run for debug
parent_path="$(dirname "${BASH_SOURCE[0]}")"
FILE=${parent_path}/update-cloudflare-dns.log
if ! [ -x "$FILE" ]; then
  touch "$FILE"
fi

LOG_FILE=${parent_path}'/update-cloudflare-dns.log'

### Write last run of STDOUT & STDERR as log file and prints to screen
exec > >(tee $LOG_FILE) 2>&1
echo "==> $(date "+%Y-%m-%d %H:%M:%S")"

### Function for Discord error notifications
send_discord_error() {
    local error_message="$1"
    curl -H "Content-Type: application/json" -d '{
        "content": null,
        "embeds": [
            {
            "title": "❌ Cloudflare Update Error",
            "description": "```'${error_message}'```",
            "color": 16711680,
            "timestamp": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"
            }
        ],
        "username": "Cloudflare DNS Updater",
        "attachments": []
    }' "${discord_webhook_url}"
}

### Validate if config-file exists
if [[ -z "$1" ]]; then
    if ! source ${parent_path}/update-cloudflare-dns.conf; then
        error_msg="Error! Missing configuration file update-cloudflare-dns.conf or invalid syntax!"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        exit 0
    fi
else
    if ! source ${parent_path}/"$1"; then
        error_msg="Error! Missing configuration file $1 or invalid syntax!"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        exit 0
    fi
fi

### Check validity of "ttl" parameter
if [ "${ttl}" -lt 120 ] || [ "${ttl}" -gt 7200 ] && [ "${ttl}" -ne 1 ]; then
    error_msg="Error! ttl out of range (120-7200) or not set to 1"
    echo "$error_msg"
    [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
    exit 0
fi

### Check validity of "proxied" parameter
if [ "${proxied}" != "false" ] && [ "${proxied}" != "true" ]; then
    error_msg='Error! Incorrect "proxied" parameter, choose "true" or "false"'
    echo "$error_msg"
    [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
    exit 0
fi

### Check validity of "what_ip" parameter
if [ "${what_ip}" != "external" ] && [ "${what_ip}" != "internal" ]; then
    error_msg='Error! Incorrect "what_ip" parameter, choose "external" or "internal"'
    echo "$error_msg"
    [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
    exit 0
fi

### Check if set to internal ip and proxy
if [ "${what_ip}" == "internal" ] && [ "${proxied}" == "true" ]; then
    error_msg='Error! Internal IP cannot be proxied'
    echo "$error_msg"
    [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
    exit 0
fi

### Valid IPv4 Regex
REIP='^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.){3}(25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])$'

### Get external ip from https://checkip.amazonaws.com
if [ "${what_ip}" == "external" ]; then
    ip=$(curl -4 -s -X GET https://checkip.amazonaws.com --max-time 10)
    if [ -z "$ip" ]; then
        error_msg="Error! Can't get external ip from https://checkip.amazonaws.com"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        exit 0
    fi
    if ! [[ "$ip" =~ $REIP ]]; then
        error_msg="Error! IP Address returned was invalid!"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        exit 0
    fi
    echo "==> External IP is: $ip"
fi

### Get Internal ip from primary interface
if [ "${what_ip}" == "internal" ]; then
    if which ip >/dev/null; then
        interface=$(ip route get 1.1.1.1 | awk '/dev/ { print $5 }')
        ip=$(ip -o -4 addr show ${interface} scope global | awk '{print $4;}' | cut -d/ -f 1)
    else
        interface=$(route get 1.1.1.1 | awk '/interface:/ { print $2 }')
        ip=$(ifconfig ${interface} | grep 'inet ' | awk '{print $2}')
    fi
    if [ -z "$ip" ]; then
        error_msg="Error! Can't read ip from ${interface}"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        exit 0
    fi
    echo "==> Internal ${interface} IP is: $ip"
fi

### Build coma separated array from dns_record parameter to update multiple A records
IFS=',' read -d '' -ra dns_records <<<"$dns_record,"
unset 'dns_records[${#dns_records[@]}-1]'
declare dns_records

for record in "${dns_records[@]}"; do
    if [ "${proxied}" == "false" ]; then
        if which nslookup >/dev/null; then
            dns_record_ip=$(nslookup ${record} 1.1.1.1 | awk '/Address/ { print $2 }' | sed -n '2p')
        else
            dns_record_ip=$(host -t A ${record} 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
        fi

        if [ -z "$dns_record_ip" ]; then
            error_msg="Error! Can't resolve ${record} via 1.1.1.1 DNS server"
            echo "$error_msg"
            [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
            continue
        fi
        is_proxed="${proxied}"
    fi

    if [ "${proxied}" == "true" ]; then
        dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
            -H "Authorization: Bearer $cloudflare_zone_api_token" \
            -H "Content-Type: application/json")
        if [[ ${dns_record_info} == *"\"success\":false"* ]]; then
            error_msg="Error! Can't get dns record info from Cloudflare API for ${record}"
            echo "$error_msg"
            [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
            continue
        fi
        is_proxed=$(echo ${dns_record_info} | grep -o '"proxied":[^,]*' | grep -o '[^:]*$')
        dns_record_ip=$(echo ${dns_record_info} | grep -o '"content":"[^"]*' | cut -d'"' -f 4)
    fi

    if [ ${dns_record_ip} == ${ip} ] && [ ${is_proxed} == ${proxied} ]; then
        echo "==> DNS record IP of ${record} is ${dns_record_ip}, no changes needed."
        continue
    fi

    echo "==> DNS record of ${record} is: ${dns_record_ip}. Trying to update..."

    cloudflare_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
        -H "Authorization: Bearer $cloudflare_zone_api_token" \
        -H "Content-Type: application/json")
    if [[ ${cloudflare_record_info} == *"\"success\":false"* ]]; then
        error_msg="Error! Can't get ${record} record information from Cloudflare API"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        continue
    fi

    cloudflare_dns_record_id=$(echo ${cloudflare_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)

    update_dns_record=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
        -H "Authorization: Bearer $cloudflare_zone_api_token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
    if [[ ${update_dns_record} == *"\"success\":false"* ]]; then
        error_msg="Error! Update failed for ${record}"
        echo "$error_msg"
        [[ "${notify_me_discord}" == "yes" ]] && send_discord_error "$error_msg"
        continue
    fi

    echo "==> Success!"
    echo "==> $record DNS Record updated to: $ip, ttl: $ttl, proxied: $proxied"

    if [ "${notify_me_discord}" == "yes" ]; then
        curl -H "Content-Type: application/json" -d '{
            "content": null,
            "embeds": [
                {
                "title": "✅ Cloudflare DNS Update Successful",
                "description": "Domain: `'${record}'`\nNew IP: `'${ip}'`\nTTL: `'${ttl}'`\nProxied: `'${proxied}'`",
                "color": 65280,
                "timestamp": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"
                }
            ],
            "username": "Cloudflare DNS Updater",
            "attachments": []
        }' "${discord_webhook_url}"
    fi
done
