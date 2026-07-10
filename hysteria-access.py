import json
import os
import threading
import time
import urllib.request

LOG = "/var/log/hysteria/server.log"
API = "http://hysteria:9999/dump/streams"
SECRET = os.environ["HYSTERIA_API_SECRET"]
INTERVAL = float(os.getenv("POLL_INTERVAL", "1"))

lock = threading.Lock()
sessions = {}


def split_host_port(address):
    host, port = address.rsplit(":", 1)
    return host.strip("[]"), int(port)


def follow_sessions():
    while not os.path.exists(LOG):
        time.sleep(0.2)
    with open(LOG, "r", encoding="utf-8", errors="replace") as log:
        log.seek(0, os.SEEK_END)
        while True:
            line = log.readline()
            if not line:
                time.sleep(0.1)
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            user = item.get("id")
            address = item.get("addr")
            if not user or not address:
                continue
            with lock:
                current = sessions.setdefault(user, set())
                if item.get("msg") == "client connected":
                    current.add(address)
                elif item.get("msg") == "client disconnected":
                    current.discard(address)
                if not current:
                    sessions.pop(user, None)


def source_for(user):
    with lock:
        addresses = list(sessions.get(user, ()))
    if len(addresses) != 1:
        return None, "ambiguous" if addresses else "unavailable"
    ip, port = split_host_port(addresses[0])
    return {"ip": ip, "port": port}, "session"


def stream_map():
    request = urllib.request.Request(API, headers={"Authorization": SECRET})
    with urllib.request.urlopen(request, timeout=2) as response:
        streams = json.load(response).get("streams", [])
    return {
        f'{item.get("auth", "unknown")}|{item["connection"]}|{item["stream"]}': item
        for item in streams
    }


def emit(item, phase):
    user = item.get("auth", "unknown")
    source, attribution = source_for(user)
    destination, port = split_host_port(item["req_addr"])
    event = {
        "@timestamp": item["initial_at"] if phase == "open" else item["last_active_at"],
        "event": {
            "kind": "event",
            "category": ["network"],
            "type": ["start" if phase == "open" else "end", "connection"],
            "action": "proxy-connect" if phase == "open" else "proxy-close",
            "outcome": "success",
        },
        "network": {"transport": "tcp", "protocol": "hysteria2"},
        "user": {"name": user},
        "destination": {
            "address": item["req_addr"],
            "domain": item.get("hooked_req_addr") or destination,
            "port": port,
        },
        "proxy": {
            "protocol": "hysteria2",
            "connection_id": str(item["connection"]),
            "stream_id": str(item["stream"]),
            "source_attribution": attribution,
        },
        "source_event": f"hysteria-stream-{phase}",
    }
    if source:
        event["source"] = source
    if phase == "close":
        event["event_start"] = item["initial_at"]
        event.setdefault("source", {})["bytes"] = item["tx"]
        event["destination_bytes"] = item["rx"]
    print(json.dumps(event, separators=(",", ":")), flush=True)


threading.Thread(target=follow_sessions, daemon=True).start()
previous = {}
while True:
    try:
        current = stream_map()
        for key in current.keys() - previous.keys():
            emit(current[key], "open")
        for key in previous.keys() - current.keys():
            emit(previous[key], "close")
        previous = current
    except Exception as error:
        print(json.dumps({"log.level": "error", "message": str(error)}), flush=True)
    time.sleep(INTERVAL)
