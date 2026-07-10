import json
import os
import re
import time
from datetime import datetime

LOG = "/var/log/sing-box/server.log"
SOURCE = re.compile(
    r"^(?P<tz>\S+) (?P<time>\S+ \S+) \S+ \[(?P<id>\d+) (?P<elapsed>\d+)ms\] "
    r"inbound/anytls\[[^\]]+\]: inbound connection from (?P<address>.+)$"
)
TARGET = re.compile(
    r"^(?P<tz>\S+) (?P<time>\S+ \S+) \S+ \[(?P<id>\d+) (?P<elapsed>\d+)ms\] "
    r"inbound/anytls\[[^\]]+\]: \[(?P<user>[^\]]+)\] inbound connection to (?P<address>.+)$"
)


def split_host_port(address):
    host, port = address.rsplit(":", 1)
    return host.strip("[]"), int(port)


def emit(source, target):
    source_ip, source_port = split_host_port(source["address"])
    destination, destination_port = split_host_port(target["address"])
    event = {
        "@timestamp": datetime.strptime(
            f'{target["time"]}{target["tz"]}', "%Y-%m-%d %H:%M:%S%z"
        ).isoformat(),
        "event": {
            "kind": "event",
            "category": ["network"],
            "type": ["start", "connection"],
            "action": "proxy-connect",
            "outcome": "success",
            "duration": int(target["elapsed"]) * 1_000_000,
        },
        "network": {"transport": "tcp", "protocol": "anytls"},
        "proxy": {"protocol": "anytls", "connection_id": target["id"]},
        "user": {"name": target["user"]},
        "source": {"ip": source_ip, "port": source_port},
        "destination": {
            "address": target["address"],
            "domain": destination,
            "port": destination_port,
        },
        "source_event": "anytls-connect",
    }
    print(json.dumps(event, separators=(",", ":")), flush=True)


while not os.path.exists(LOG):
    time.sleep(0.2)

sources = {}
with open(LOG, "r", encoding="utf-8", errors="replace") as log:
    log.seek(0, os.SEEK_END)
    while True:
        line = log.readline()
        if not line:
            time.sleep(0.1)
            continue
        line = line.strip()
        match = SOURCE.match(line)
        if match:
            sources[match["id"]] = match.groupdict()
            continue
        match = TARGET.match(line)
        if match:
            source = sources.pop(match["id"], None)
            if source:
                emit(source, match.groupdict())
