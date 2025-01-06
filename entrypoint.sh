#!/bin/bash

# Set proper permissions for nginx and streamdata
mkdir -p /var/www/hls
mkdir -p /var/www/hls/pids
mkdir -p /var/www/streamdata/metadata/images

chown -R nginx:nginx /var/www/hls /var/www/streamdata
chmod -R 755 /var/www/hls /var/www/streamdata

# Create empty streams.json if it does not exist
if [ ! -f /var/www/hls/streams.json ]; then
    echo '{"streams": []}' > /var/www/hls/streams.json
fi

# Start nginx in the background
nginx &

# Start Flask app in the background
python3 /app/app.py &

# Start stream converter in the background
/usr/local/bin/stream-converter.sh &

# Wait a moment for nginx and Flask to start
sleep 2

# Check if nginx is running
if ! pgrep nginx > /dev/null; then
    echo "Error: nginx failed to start"
    exit 1
fi

# Check if Flask is running
if ! pgrep -f "python3 /app/app.py" > /dev/null; then
    echo "Error: Flask app failed to start"
    exit 1
fi

echo "Nginx, Flask app, and Stream Converter started successfully"

# Keep the container running
wait