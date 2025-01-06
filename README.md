# ShiestyCast
A docker container that currently supports adding icecast streams to restream in hls format. it uses ffmpeg to rebroadcast the icecast stream, uploads it as a .m3u8 as well as a master.m3u to a link reachable on your local network.

# Stream Converter

This Docker container converts Shoutcast/Icecast/MP3 streams to HLS (m3u8) format for compatibility with players like VLC and web browsers.

## Quick Start

1. **Build and start the container:**
    ```bash
    docker-compose up -d
    ```

2. **Access the Web Interface:**
    Open your browser and navigate to `http://localhost:5000` to manage your streams.

## Managing Streams

### **Add a New Stream**

1. Go to the web interface at `http://localhost:5000`.
2. Fill in the **Stream Name**, **Source URL**, and **Output Path** (e.g., `/my/folder/customname.m3u8`).
3. Click **Add Stream**.

### **Edit an Existing Stream**

1. In the streams table, click **Edit** next to the stream you want to modify.
2. Update the **Source URL** or **Output Path** as needed.
3. Click **Update**.

### **Delete a Stream**

1. In the streams table, click **Delete** next to the stream you want to remove.
2. Confirm the deletion when prompted.

## Accessing Streams

For each configured stream, access it using its custom output path. For example:

- `http://localhost:9090/hls/my/folder/customname.m3u8`

## Usage with VLC

1. Open VLC.
2. Go to **Media > Open Network Stream**.
3. Enter the URL of the desired stream (e.g., `http://localhost:9090/hls/my/folder/customname.m3u8`).
4. Click **Play**.

## Configuration

The container manages streams through a JSON configuration file located at `/var/www/hls/streams.json`. You can also edit this file directly if needed.

### **Example `streams.json`**
