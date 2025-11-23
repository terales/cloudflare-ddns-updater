#!/bin/bash
AUTH_EMAIL="${CF_AUTH_EMAIL:-your_email@example.com}"
AUTH_TOKEN="${CF_API_TOKEN:-your_api_token}"
ZONE_ID="${CF_ZONE_ID:-your_zone_id}"
RECORD_NAME="${CF_RECORD_NAME:-subdomain.example.com}"
DISCORD_URI="${DISCORD_WEBHOOK_URI:-}" # Leave empty to disable
TTL="${CF_TTL:-60}"

CACHE_FILE="/tmp/cloudflare_ddns_${RECORD_NAME}.cache"

# Enable strict error handling
set -euo pipefail

# Function to log messages
log() {
    logger -s -t "DDNS-Updater" "$1"
}

# Function to send Discord notification
notify_discord() {
    local msg="$1"
    if [[ -n "$DISCORD_URI" ]]; then
        # 'xh' handles json construction automatically
        xh POST "$DISCORD_URI" content="$msg" --ignore-stdin >/dev/null 2>&1 || true
    fi
}

###########################################
## 1. Get Public IP
###########################################

# More robust regex for IPv4
REGEX_IPV4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
DNS_PROVIDERS=(
  "txt ch whoami.cloudflare @1.1.1.1"
  "txt o-o.myaddr.l.google.com @ns1.google.com"
  "myip.opendns.com @resolver1.opendns.com"
  "any whoami.akamai.net @ns1-1.akamaitech.net"
)

CURRENT_IP=""

for cmd in "${DNS_PROVIDERS[@]}"; do
    # Using +short usually returns just the IP, cleaner than parsing full output
    # Splitting cmd string into args for dig
    # shellcheck disable=SC2086
    RAW_IP=$(dig +time=1 +tries=1 +short $cmd | tr -d '"\n' || true)

    if [[ $RAW_IP =~ $REGEX_IPV4 ]]; then
        CURRENT_IP="$RAW_IP"
        break
    fi
done

if [[ -z "$CURRENT_IP" ]]; then
    log "Error: Failed to find a valid public IP."
    exit 1
fi

###########################################
## 2. Check Local Cache
###########################################

CACHED_IP=""
RECORD_ID=""

if [[ -f "$CACHE_FILE" ]]; then
    # Read first two lines: IP and ID
    {
        read -r CACHED_IP || true
        read -r RECORD_ID || true
    } < "$CACHE_FILE"
fi

if [[ -n "$CACHED_IP" ]]; then
    if [[ "$CURRENT_IP" == "$CACHED_IP" ]]; then
        # 1. Match: Exit immediately
        exit 0
    else
        # 2. Change Detected
        log "IP changed (Old: $CACHED_IP, New: $CURRENT_IP). Attempting update."
    fi
else
    # 3. First Run / No Cache
    log "No local cache found. Initializing update for $CURRENT_IP."
fi

###########################################
## 3. Update Cloudflare if record ID is in cache
###########################################

update_success="false"

# Helper function to patch record
patch_record() {
    local id="$1"
    # xh syntax: key=value (string), key:=value (literal/bool/int)
    xh PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$id" \
        "X-Auth-Email:$AUTH_EMAIL" \
        "Authorization:Bearer $AUTH_TOKEN" \
        type="A" \
        name="$RECORD_NAME" \
        content="$CURRENT_IP" \
        ttl:=$TTL \
        proxied:=false \
        --check-status \
        --ignore-stdin 2>/dev/null
}

# Strategy: If we have a Record ID, try to PATCH directly.
# This saves a GET request on every IP change.
if [[ -n "$RECORD_ID" && "$RECORD_ID" != "null" ]]; then
    if response=$(patch_record "$RECORD_ID"); then
        update_success="true"
    else
        log "Direct update failed (ID might be invalid). Falling back to lookup."
    fi
fi

###########################################
## 4. Lookup & Update (Fallback)
###########################################

if [[ "$update_success" != "true" ]]; then
    log "Querying Cloudflare for Record ID..."

    # Get Record ID
    record_info=$(xh GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
        "X-Auth-Email:$AUTH_EMAIL" \
        "Authorization:Bearer $AUTH_TOKEN" \
        --ignore-stdin)

    # Extract ID and Content
    read -r RECORD_ID REMOTE_IP <<< "$(echo "$record_info" | jq -r '.result[0] | "\(.id) \(.content)"')"

    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
        log "Error: Record $RECORD_NAME not found in zone."
        notify_discord "$RECORD_NAME DDNS failed: Record not found."
        exit 1
    fi

    # Edge case: Maybe the IP was actually correct on Cloudflare but our local cache was wrong/deleted
    if [[ "$CURRENT_IP" == "$REMOTE_IP" ]]; then
        echo -e "$CURRENT_IP\n$RECORD_ID" > "$CACHE_FILE"
        update_success="true" # Technically not an update, but we are synced
        log "Cloudflare is already up to date. Updated local cache only."
    else
        # Perform the update with the fresh ID
        if response=$(patch_record "$RECORD_ID"); then
            update_success="true"
        else
            error_dump=$(echo "$response" | jq -c .)
            log "Update failed: $error_dump"
            notify_discord "$RECORD_NAME DDNS update failed."
            exit 1
        fi
    fi
fi

###########################################
## 5. Success Handling
###########################################

if [[ "$update_success" == "true" ]]; then
    # Update Cache
    echo -e "$CURRENT_IP\n$RECORD_ID" > "$CACHE_FILE"

    log "Success: $RECORD_NAME updated to $CURRENT_IP."
    notify_discord "$RECORD_NAME updated: new IP Address is $CURRENT_IP"
    exit 0
fi
