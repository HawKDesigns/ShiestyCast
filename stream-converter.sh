#!/bin/bash

# Path to the streams configuration file
STREAMS_FILE=/var/www/hls/streams.json

# Directory to store ffmpeg process IDs
PID_DIR=/var/www/hls/pids

# Directory to store master playlist and metadata
STREAMDATA_DIR=/var/www/streamdata
IMAGE_DIR=${STREAMDATA_DIR}/metadata/images
MASTER_PLAYLIST=${STREAMDATA_DIR}/master.m3u

# Base URL for streams
BASE_URL="http://localhost:9090/hls/"

mkdir -p "$PID_DIR"
mkdir -p "$IMAGE_DIR"

# Function to sanitize stream names (optional)
sanitize_name() {
    echo "$1" | tr ' ' '_'
}

# Function to start a stream
start_stream() {
    local name="$1"
    local source_url="$2"
    local output_path="$3"
    local channel_id="$4"  # Receive channel_id as a parameter

    # Optional: Sanitize the name to replace spaces with underscores
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")

    # Correctly set the full output path without removing any part of the output_path
    local full_output_path="/var/www/hls/${output_path}"
    local output_dir
    output_dir=$(dirname "$full_output_path")

    # Create directory if it doesn't exist
    mkdir -p "$output_dir"

    # Set permissions
    chown -R nginx:nginx "$output_dir"
    chmod -R 755 "$output_dir"

    # Extract bitrate
    SOURCE_BITRATE=$(ffmpeg -i "$source_url" 2>&1 | grep "bitrate:" | awk '{print $6}')

    if [[ "$SOURCE_BITRATE" =~ ^[0-9]+$ ]]; then
        SOURCE_BITRATE="${SOURCE_BITRATE}k"
    fi

    if [ -z "$SOURCE_BITRATE" ]; then
        SOURCE_BITRATE=192k
        echo "Warning: Unable to detect source bitrate for $name. Using default ${SOURCE_BITRATE}."
    else
        echo "Detected source bitrate for $name: ${SOURCE_BITRATE}"
    fi

    # Start ffmpeg process
    ffmpeg -i "$source_url" \
        -c:a aac \
        -b:a "$SOURCE_BITRATE" \
        -map 0:a \
        -f hls \
        -hls_time 10 \
        -hls_list_size 6 \
        -hls_flags delete_segments \
        -hls_segment_filename "${output_dir}/segment_%03d.ts" \
        "$full_output_path" &

    # Save PID with sanitized name
    echo $! > "${PID_DIR}/${sanitized_name}.pid"
    echo "Started stream: $name with PID $(cat "${PID_DIR}/${sanitized_name}.pid")"
}

# Function to stop a stream
stop_stream() {
    local name="$1"
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")

    local pid_file="${PID_DIR}/${sanitized_name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        kill "$pid"
        echo "Stopped stream: $name"
    else
        echo "PID file not found for stream: $name"
    fi
}

# Function to restart a stream
restart_stream() {
    local name="$1"
    local source_url="$2"
    local output_path="$3"
    local channel_id="$4"

    stop_stream "$name"
    start_stream "$name" "$source_url" "$output_path" "$channel_id"
}

# Function to load streams from JSON
load_streams() {
    jq -c '.streams[]' "$STREAMS_FILE"
}

# Initialize
declare -A CURRENT_STREAMS

# Monitor streams.json and manage streams
while true; do
    if [ ! -f "$STREAMS_FILE" ]; then
        echo "Streams configuration file not found. Waiting..."
        sleep 5
        continue
    fi

    # Read current streams
    mapfile -t STREAMS < <(load_streams)

    # Track current stream names
    declare -A NEW_STREAMS
    for stream in "${STREAMS[@]}"; do
        name=$(echo "$stream" | jq -r '.name')
        source_url=$(echo "$stream" | jq -r '.source_url')
        output_path=$(echo "$stream" | jq -r '.output_path')
        channel_id=$(echo "$stream" | jq -r '.channel_id')
        NEW_STREAMS["$name"]="$source_url|$output_path|$channel_id"

        if [ -z "${CURRENT_STREAMS[$name]}" ]; then
            # New stream added
            echo "Adding new stream: $name"
            start_stream "$name" "$source_url" "$output_path" "$channel_id"
        else
            # Check if stream configuration has changed
            IFS='|' read -r current_source current_output current_channel <<< "${CURRENT_STREAMS[$name]}"
            if [ "$source_url" != "$current_source" ] || [ "$output_path" != "$current_output" ]; then
                echo "Updating stream: $name"
                restart_stream "$name" "$source_url" "$output_path" "$channel_id"
            fi
        fi
    done

    # Stop removed streams
    for name in "${!CURRENT_STREAMS[@]}"; do
        if [ -z "${NEW_STREAMS[$name]}" ]; then
            echo "Removing stream: $name"
            stop_stream "$name"
        fi
    done

    # Update current streams
    CURRENT_STREAMS=()
    for stream in "${STREAMS[@]}"; do
        name=$(echo "$stream" | jq -r '.name')
        source_url=$(echo "$stream" | jq -r '.source_url')
        output_path=$(echo "$stream" | jq -r '.output_path')
        channel_id=$(echo "$stream" | jq -r '.channel_id')
        CURRENT_STREAMS["$name"]="$source_url|$output_path|$channel_id"
    done

    sleep 5
done