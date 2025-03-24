import os
import json
import subprocess
import requests
import socket
from flask import Flask, jsonify, render_template, request, redirect, url_for

app = Flask(__name__)

# File to store server data
SERVERS_FILE = "servers.json"

# Logging configuration
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler("app.log"),
        logging.StreamHandler()
    ]
)

# Load server data from JSON file
def load_servers():
    try:
        if not os.path.exists(SERVERS_FILE):
            logging.warning(f"{SERVERS_FILE} not found. Creating a new file.")
            return []
        with open(SERVERS_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Failed to load {SERVERS_FILE}: {e}")
        return []

# Save server data to JSON file
def save_servers(servers):
    try:
        with open(SERVERS_FILE, "w") as f:
            json.dump(servers, f, indent=4)  # Save the updated server list
    except Exception as e:
        logging.error(f"Failed to save {SERVERS_FILE}: {e}")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/adminpanel', methods=['GET', 'POST'])
def manage():
    if request.method == 'POST':
        action = request.form.get("action")
        name = request.form.get("name")
        target = request.form.get("target")
        check_type = request.form.get("type")

        servers = load_servers()

        if action == "add":
            # Validate inputs
            if not name or not target or not check_type:
                return jsonify({"error": "Missing required fields"}), 400
            servers.append({
                "name": name,
                "target": target,
                "type": check_type,
                "enabled": True
            })
        elif action == "remove":
            servers = [s for s in servers if s["name"] != name]
        elif action == "toggle":
            # Find the server by name and toggle its "enabled" status
            for server in servers:
                if server["name"] == name:
                    server["enabled"] = not server["enabled"]  # Toggle the enabled status
                    break  # Exit loop once the server is found

        # Save the updated server list to the JSON file
        save_servers(servers)

        # Redirect to GET request to prevent duplicate submissions
        return redirect(url_for('manage'))

    # For GET requests, simply load and render the server list
    servers = load_servers()
    return render_template('manage.html', servers=servers)

def is_ping_successful(target, timeout=5):
    """Check if the target responds to ICMP ping."""
    try:
        output = subprocess.run(
            ["ping", "-c", "1", "-W", "3", target],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout
        )
        logging.info(f"Ping stdout for {target}: {output.stdout}")
        logging.info(f"Ping stderr for {target}: {output.stderr}")
        return output.returncode == 0
    except Exception as e:
        logging.error(f"Ping failed for {target}: {e}")
        return False

def is_dns_resolvable(target):
    """Check if the target domain resolves to an IP address."""
    try:
        ip_address = socket.gethostbyname(target)
        logging.info(f"DNS resolution succeeded for {target}: {ip_address}")
        return True
    except socket.gaierror as e:
        logging.error(f"DNS resolution failed for {target}: {e}")
        return False

def is_tcp_handshake_successful(target, port=80, timeout=5):
    """Check if a TCP handshake succeeds with the target."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((target, port))
        sock.close()
        if result == 0:
            logging.info(f"TCP handshake succeeded for {target}:{port}")
            return True
        else:
            logging.info(f"TCP handshake failed for {target}:{port}")
            return False
    except Exception as e:
        logging.error(f"TCP handshake failed for {target}:{port}: {e}")
        return False

@app.route('/status/<server_name>')
def status(server_name):
    servers = load_servers()
    server = next((s for s in servers if s["name"] == server_name), None)
    if not server or not server["enabled"]:
        return jsonify({"error": "Server not found or disabled"}), 404

    status = "Offline"
    target = server["target"]

    # Primary check: Ping
    if is_ping_successful(target):
        status = "Online"
    else:
        # Fallback 1: DNS resolution
        if is_dns_resolvable(target):
            # Fallback 2: TCP handshake
            if is_tcp_handshake_successful(target):
                status = "Online"
            else:
                status = "Partial Connectivity (TCP handshake failed)"
        else:
            status = "Offline (DNS resolution failed)"

    return jsonify({"name": server["name"], "status": status})

@app.route('/status')
def all_status():
    servers = load_servers()
    results = []
    for server in servers:
        if not server["enabled"]:
            continue
        target = server["target"]
        status = "Offline"

        # Primary check: Ping
        if is_ping_successful(target):
            status = "Online"
        else:
            # Fallback 1: DNS resolution
            if is_dns_resolvable(target):
                # Fallback 2: TCP handshake
                if is_tcp_handshake_successful(target):
                    status = "Online"
                else:
                    status = "Partial Connectivity (TCP handshake failed)"
            else:
                status = "Offline (DNS resolution failed)"

        results.append({"name": server["name"], "status": status})
    return jsonify(results)

if __name__ == '__main__':
    app.run(debug=False)  # Disable debug mode for production
