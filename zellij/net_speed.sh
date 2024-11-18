#!/usr/bin/env bash

# Network interface to monitor (e.g., eth0, wlan0)
INTERFACE="eth0"
# Temporary files to store the previous bytes
RX_PREV_FILE="/tmp/rx_prev"
TX_PREV_FILE="/tmp/tx_prev"

# Function to get the current bytes received and transmitted
get_bytes() {
    RX_BYTES=$(awk "/$INTERFACE/ {print \$2}" /proc/net/dev)
    TX_BYTES=$(awk "/$INTERFACE/ {print \$10}" /proc/net/dev)
}

# Function to format speed with appropriate units
format_speed() {
    local BYTES=$1
    if [ "$BYTES" -ge $((1024 * 1024 * 1024)) ]; then
        echo "$((BYTES / (1024 * 1024 * 1024))) GB/s"
    elif [ "$BYTES" -ge $((1024 * 1024)) ]; then
        echo "$((BYTES / (1024 * 1024))) MB/s"
    elif [ "$BYTES" -ge 1024 ]; then
        echo "$((BYTES / 1024)) KB/s"
    else
        echo "$BYTES B/s"
    fi
}

# Initialize previous bytes if not set
if [ ! -f "$RX_PREV_FILE" ] || [ ! -f "$TX_PREV_FILE" ]; then
    get_bytes
    echo "$RX_BYTES" > "$RX_PREV_FILE"
    echo "$TX_BYTES" > "$TX_PREV_FILE"
    echo "Initializing previous data. Please run the script again."
    exit 0
fi

# Read previous values
RX_PREV=$(cat "$RX_PREV_FILE")
TX_PREV=$(cat "$TX_PREV_FILE")

# Get current bytes
get_bytes

# Calculate speed in bytes per second
RX_DIFF=$((RX_BYTES - RX_PREV))
TX_DIFF=$((TX_BYTES - TX_PREV))

# Store the current bytes for the next execution
echo "$RX_BYTES" > "$RX_PREV_FILE"
echo "$TX_BYTES" > "$TX_PREV_FILE"

# Format the speed and display
RX_SPEED=$(format_speed "$RX_DIFF")
TX_SPEED=$(format_speed "$TX_DIFF")

echo "D: $RX_SPEED U: $TX_SPEED"
