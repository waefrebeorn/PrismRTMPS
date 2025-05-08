#!/bin/bash
set -e

NGINX_TEMPLATE=/etc/nginx/nginx.conf.template
NGINX_CONF=/etc/nginx/nginx.conf
VALIDATOR_LOG=/tmp/validator.log
ENV_OK=0
MAX_WAIT_VALIDATOR_SECONDS=15 # Maximum seconds to wait for validator
VALIDATOR_CHECK_INTERVAL_SECONDS=0.2 # Check every 200ms

# !!! Removed MASTER_STREAM_KEY check !!!
# The container will now start without it, relying on destination keys for validation.

echo "Starting stream key validation server..."
# Start in background, redirect stdout/stderr to a log file
python3 /stream_validator.py > "$VALIDATOR_LOG" 2>&1 &
VALIDATOR_PID=$!
echo "Validator PID: $VALIDATOR_PID"

# --- Robust Validator Check ---
echo "Waiting for validator to be ready..."
VALIDATOR_READY=0
# Calculate maximum attempts based on total wait time and interval
# Use awk for floating point division and ceiling to integer
MAX_ATTEMPTS=$(awk -v max_wait="$MAX_WAIT_VALIDATOR_SECONDS" -v interval="$VALIDATOR_CHECK_INTERVAL_SECONDS" 'BEGIN {printf "%.0f", max_wait / interval}')
CURRENT_ATTEMPT=0

while [ $CURRENT_ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Check if process exists AND responds to health check
    # Added --connect-timeout and reduced --max-time for curl
    if kill -0 $VALIDATOR_PID 2>/dev/null && curl --fail --silent --connect-timeout 0.1 --max-time 0.4 http://127.0.0.1:8080/health > /dev/null; then
        echo "Validator is running and responding."
        VALIDATOR_READY=1
        break
    fi

    # Log approximately every second to avoid excessive verbosity
    # (e.g., if interval is 0.2s, log every 5 attempts)
    LOG_THROTTLE_ATTEMPTS=$(awk -v interval="$VALIDATOR_CHECK_INTERVAL_SECONDS" 'BEGIN {printf "%.0f", 1 / interval}')
    if [ $((CURRENT_ATTEMPT % LOG_THROTTLE_ATTEMPTS)) -eq 0 ] || [ $CURRENT_ATTEMPT -eq 0 ]; then
        ELAPSED_SECONDS_APPROX=$(awk -v current_attempt="$CURRENT_ATTEMPT" -v interval="$VALIDATOR_CHECK_INTERVAL_SECONDS" 'BEGIN {printf "%.1f", current_attempt * interval}')
        echo "Validator not ready yet, waiting... (${ELAPSED_SECONDS_APPROX}s / ${MAX_WAIT_VALIDATOR_SECONDS}s)"
    fi
    sleep $VALIDATOR_CHECK_INTERVAL_SECONDS
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
done

if [ $VALIDATOR_READY -eq 0 ]; then
    ELAPSED_SECONDS_FINAL=$(awk -v current_attempt="$CURRENT_ATTEMPT" -v interval="$VALIDATOR_CHECK_INTERVAL_SECONDS" 'BEGIN {printf "%.1f", current_attempt * interval}')
    echo "ERROR: Stream key validator failed to start or respond within ${ELAPSED_SECONDS_FINAL}s (max ${MAX_WAIT_VALIDATOR_SECONDS}s)."
    echo "Check validator logs:"
    cat "$VALIDATOR_LOG"
    exit 1
fi
# --- End Validator Check ---


# --- Configure Nginx based on Environment Variables ---
# Use a temporary file for sed modifications
TMP_TEMPLATE=$(mktemp)
cp $NGINX_TEMPLATE $TMP_TEMPLATE

echo "Configuring Nginx push destinations..."

# Function to add push directive if key is present
add_push() {
    local platform_name="$1"
    local env_key_var="$2"
    local env_url_var="$3"
    local template_marker="$4"
    local push_url="${!env_url_var}" # Indirect variable expansion
    local key_value="${!env_key_var}" # Indirect variable expansion

    if [ -n "$key_value" ]; then
        if [ -z "$push_url" ]; then
             echo "Warning: ${platform_name} key (${env_key_var}) is set, but URL (${env_url_var}) is empty. Skipping push."
             sed -i "s|#${template_marker}| |g" $TMP_TEMPLATE
        else
            echo "${platform_name} activated."
            # Correctly escape slashes in URLs for sed, use | as delimiter
            local escaped_push="push ${push_url}${key_value};"
            sed -i "s|#${template_marker}|${escaped_push}|g" $TMP_TEMPLATE
            ENV_OK=1
       fi
    else
        # Remove the placeholder comment if key is not set
        sed -i "s|#${template_marker}| |g" $TMP_TEMPLATE
    fi
}

# Add pushes for each platform using the function
add_push "Youtube"    "YOUTUBE_KEY"    "YOUTUBE_URL"    "youtube"
add_push "Facebook"   "FACEBOOK_KEY"   "FACEBOOK_URL"   "facebook"
add_push "Instagram"  "INSTAGRAM_KEY"  "INSTAGRAM_URL"  "instagram"
add_push "Cloudflare" "CLOUDFLARE_KEY" "CLOUDFLARE_URL" "cloudflare"
add_push "Twitch"     "TWITCH_KEY"     "TWITCH_URL"     "twitch"
add_push "Kick"       "KICK_KEY"       "KICK_URL"       "kick"
add_push "X (Twitter)" "X_KEY"          "X_URL"          "x"
add_push "Trovo"      "TROVO_KEY"      "TROVO_URL"      "trovo"
add_push "RTMP1"      "RTMP1_KEY"      "RTMP1_URL"      "rtmp1"
add_push "RTMP2"      "RTMP2_KEY"      "RTMP2_URL"      "rtmp2"
add_push "RTMP3"      "RTMP3_KEY"      "RTMP3_URL"      "rtmp3"


if [ $ENV_OK -eq 1 ]; then
    echo "Generating final Nginx configuration..."
    # Use envsubst for any remaining ${VAR} placeholders (though we added most via sed now)
    # Define the list of variables envsubst should consider
    EXPORT_VARS=$(printf '${%s} ' $(env | cut -d= -f1))
    envsubst "$EXPORT_VARS" < $TMP_TEMPLATE > $NGINX_CONF
    rm $TMP_TEMPLATE # Clean up temp file
else
    echo "Warning: No destination stream keys provided. Nginx will start, but no streams will be pushed, and no incoming streams will be accepted."
    # Still generate config from template, it will just have no push directives
    # Define the list of variables envsubst should consider even if no ENV_OK
    EXPORT_VARS=$(printf '${%s} ' $(env | cut -d= -f1))
    envsubst "$EXPORT_VARS" < $TMP_TEMPLATE > $NGINX_CONF
    rm $TMP_TEMPLATE
fi

# Debug output if requested
if [ -n "${DEBUG}" ]; then
    echo "--- Final Nginx Configuration (${NGINX_CONF}) ---"
    cat $NGINX_CONF
    echo "-------------------------------------------------"
fi

echo "Starting Stunnel..."
# Start stunnel in the background
stunnel4 /etc/stunnel/stunnel.conf

echo "Starting Nginx..."
exec "$@" # Execute the CMD from Dockerfile (nginx -g 'daemon off;')
