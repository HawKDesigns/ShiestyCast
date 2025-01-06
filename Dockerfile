FROM alpine:3.18

# Install required packages
RUN apk add --no-cache \
    ffmpeg \
    bash \
    curl \
    nginx \
    python3 \
    py3-pip \
    jq \
    util-linux

# Install Flask
RUN pip3 install Flask

# Create directories for HLS segments, Flask app, and streamdata
RUN mkdir -p /var/www/hls/pids
RUN mkdir -p /var/www/streamdata/metadata/images
RUN mkdir -p /app/templates

# Set permissions
RUN chown -R nginx:nginx /var/www/hls /var/www/streamdata
RUN chmod -R 755 /var/www/hls /var/www/streamdata

# Copy stream conversion script
COPY stream-converter.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/stream-converter.sh

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy Flask app
COPY app.py /app/
COPY templates/index.html /app/templates/

# Expose necessary ports
EXPOSE 9090 5000

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"] 