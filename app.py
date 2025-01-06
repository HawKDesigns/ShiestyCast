from flask import Flask, request, render_template, redirect, url_for, jsonify
import os
import json
from threading import Lock
from werkzeug.utils import secure_filename
import uuid
import shutil
import signal
import urllib.parse  # Added import for URL parsing

app = Flask(__name__)

# Configuration
CONFIG_PATH = '/var/www/hls/streams.json'
LOCK = Lock()
STREAMDATA_DIR = '/var/www/streamdata'
IMAGE_DIR = os.path.join(STREAMDATA_DIR, 'metadata', 'images')
ALLOWED_EXTENSIONS = {'png', 'svg'}

# Base URL for constructing logo URLs
BASE_URL = "http://localhost:9090/"  # Update this if your server uses a different base URL

# Ensure directories exist
os.makedirs(IMAGE_DIR, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def load_streams():
    with LOCK:
        if not os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, 'w') as f:
                json.dump({"streams": []}, f, indent=4)
        with open(CONFIG_PATH, 'r') as f:
            return json.load(f)

def save_streams(data):
    with LOCK:
        temp_path = CONFIG_PATH + '.tmp'
        with open(temp_path, 'w') as f:
            json.dump(data, f, indent=4)
        os.replace(temp_path, CONFIG_PATH)

def update_master_playlist(streams):
    """Update the master playlist atomically"""
    master_playlist = os.path.join(STREAMDATA_DIR, 'master.m3u')
    temp_playlist = master_playlist + '.tmp'
    
    with open(temp_playlist, 'w') as f:
        f.write('#EXTM3U url-tvg="/metadata/linktomastertvxml/master.xml.gz"\n')
        for idx, stream in enumerate(streams, 1):
            name = stream['name']
            output_path = stream['output_path']
            channel_id = stream.get('channel_id', '')
            sanitized_name = name.replace(' ', '_')
            tvg_logo = f"/metadata/images/{sanitized_name}.png"
            
            # Construct the full URL for the stream
            full_stream_url = f"http://localhost:9090/hls/{output_path.lstrip('/')}"
            
            f.write(f'#EXTINF:-1 channel-id="{channel_id}" tvg-id="{channel_id}" '
                   f'tvg-chno="{idx}" tvg-name="{name}" tvg-logo="{tvg_logo}" '
                   f'group-title="Movies", {name}\n')
            f.write(f'{full_stream_url}\n')

    # Atomic replacement of the playlist file
    os.replace(temp_playlist, master_playlist)

@app.route('/', methods=['GET', 'POST'])
def index():
    streams = load_streams().get("streams", [])
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'add':
            name = request.form.get('name')
            source_url = request.form.get('source_url')
            output_path = request.form.get('output_path')
            logo = request.files.get('logo')
            if name and source_url and output_path:
                channel_id = str(uuid.uuid4())
                new_stream = {
                    "name": name,
                    "source_url": source_url,
                    "output_path": output_path,
                    "channel_id": channel_id
                }
                if logo and allowed_file(logo.filename):
                    filename = secure_filename(logo.filename)
                    file_ext = filename.rsplit('.', 1)[1].lower()
                    logo_filename = f"{name.replace(' ', '_')}.{file_ext}"
                    logo_path = os.path.join(IMAGE_DIR, logo_filename)
                    logo.save(logo_path)
                    # Store the full URL for the logo using BASE_URL
                    new_stream["logo"] = f"{BASE_URL}metadata/images/{logo_filename}"
                data = load_streams()
                data["streams"].append(new_stream)
                save_streams(data)
                
                # Update the master playlist after adding a new stream
                update_master_playlist(data["streams"])
                
                return redirect(url_for('index'))
        elif action == 'edit':
            index = int(request.form.get('index'))
            name = request.form.get('name')
            source_url = request.form.get('source_url')
            output_path = request.form.get('output_path')
            logo = request.files.get('logo')
            if name and source_url and output_path:
                data = load_streams()
                if 0 <= index < len(data["streams"]):
                    stream = data["streams"][index]
                    stream["name"] = name
                    stream["source_url"] = source_url
                    stream["output_path"] = output_path
                    if logo and allowed_file(logo.filename):
                        filename = secure_filename(logo.filename)
                        file_ext = filename.rsplit('.', 1)[1].lower()
                        logo_filename = f"{name.replace(' ', '_')}.{file_ext}"
                        logo_path = os.path.join(IMAGE_DIR, logo_filename)
                        logo.save(logo_path)
                        # Store the full URL for the logo using BASE_URL
                        stream["logo"] = f"{BASE_URL}metadata/images/{logo_filename}"
                    data["streams"][index] = stream
                    save_streams(data)
                return redirect(url_for('index'))
        elif action == 'delete':
            index = int(request.form.get('index'))
            data = load_streams()
            if 0 <= index < len(data["streams"]):
                stream = data["streams"][index]
                
                # 1. Stop the stream first
                pid_name = stream["name"].replace(' ', '_')
                pid_file = os.path.join('/var/www/hls/pids', f"{pid_name}.pid")
                if os.path.exists(pid_file):
                    try:
                        with open(pid_file, 'r') as f:
                            pid = int(f.read().strip())
                        os.kill(pid, signal.SIGTERM)
                    except (ProcessLookupError, ValueError, FileNotFoundError):
                        pass
                    finally:
                        if os.path.exists(pid_file):
                            os.remove(pid_file)

                # 2. Remove the logo if it exists
                logo_path = stream.get("logo")
                if logo_path:
                    parsed_url = urllib.parse.urlparse(logo_path)
                    relative_path = parsed_url.path  # Extracts '/metadata/images/name.png'
                    full_logo_path = os.path.join(STREAMDATA_DIR, relative_path.lstrip('/'))
                    if os.path.exists(full_logo_path):
                        try:
                            os.remove(full_logo_path)
                        except Exception as e:
                            app.logger.error(f"Error deleting logo file {full_logo_path}: {e}")

                # 3. Clean up stream output directory
                output_dir = os.path.join('/var/www/hls', os.path.dirname(stream["output_path"].lstrip('/')))
                pid_name = stream["name"].replace(' ', '_')
                pid_file = os.path.join('/var/www/hls/pids', f"{pid_name}.pid")
                if os.path.exists(pid_file):
                    os.remove(pid_file)
                if os.path.exists(output_dir):
                    try:
                        shutil.rmtree(output_dir)
                    except Exception as e:
                        app.logger.error(f"Error deleting directory {output_dir}: {e}")

                # 4. Remove from configuration and save
                data["streams"].pop(index)
                save_streams(data)

                # 5. Force update of master playlist
                update_master_playlist(data["streams"])

            return redirect(url_for('index'))
    return render_template('index.html', streams=streams)

@app.route('/api/streams', methods=['GET'])
def get_streams():
    return jsonify(load_streams())

@app.route('/success')
def success():
    return "Stream configuration has been updated successfully!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000) 