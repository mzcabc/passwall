import base64
import ipaddress
import json
import os
import re
import shutil
import ssl
import time
import urllib.error
import urllib.request
from datetime import datetime

LOG = "/var/log/sing-box/server.log"
ES_URL = os.environ["ELASTICSEARCH_HOSTS"].split(",", 1)[0].rstrip("/")
ES_USER = os.environ["ELASTICSEARCH_USERNAME"]
ES_PASSWORD = os.environ["ELASTICSEARCH_PASSWORD"]
OBSERVER_NAME = os.getenv("HOSTNAME", "unknown")
OBSERVER_HOSTNAME = os.getenv("OBSERVER_HOSTNAME", OBSERVER_NAME)
SERVICE_VERSION = os.getenv("SING_BOX_VERSION", "1.13.14")
MAX_LOG_BYTES = int(os.getenv("MAX_LOG_BYTES", "104857600"))
STATE_TTL = float(os.getenv("STATE_TTL_SECONDS", "300"))

LINE = re.compile(
    r"^(?P<tz>[+-]\d{4}) (?P<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) "
    r"(?P<level>\S+) \[(?P<id>\d+) (?P<elapsed>[^]]+)\] "
    r"(?P<component>[^:]+): (?P<message>.*)$"
)
INBOUND = re.compile(r"^inbound/(?P<protocol>[^[]+)\[(?P<tag>[^]]+)\]$")
SOURCE = re.compile(r"^inbound (?P<packet>packet )?connection from (?P<address>.+)$")
TARGET = re.compile(
    r"^\[(?P<user>[^]]+)\] inbound (?P<packet>packet )?connection to (?P<address>.+)$"
)
UOT_TARGET = re.compile(r"^inbound UoT connection to (?P<address>.+)$")
FAILURE = re.compile(r"^process connection from (?P<address>.+?): (?P<error>.+)$")
FALLBACK = re.compile(r"^fallback connection to (?P<target>.+)$")


def split_address(value):
    host, port = value.rsplit(":", 1)
    return host.strip("[]"), int(port)


def elapsed_ns(value):
    units = {"ns": 1, "µs": 1_000, "us": 1_000, "ms": 1_000_000, "s": 1_000_000_000}
    match = re.fullmatch(r"([0-9.]+)(ns|µs|us|ms|s)", value)
    return int(float(match.group(1)) * units[match.group(2)]) if match else None


def timestamp(parts):
    return datetime.strptime(
        f'{parts["time"]}{parts["tz"]}', "%Y-%m-%d %H:%M:%S%z"
    ).isoformat()


def network_type(ip):
    return f"ipv{ipaddress.ip_address(ip).version}"


def destination(value):
    host, port = split_address(value)
    result = {"address": value, "port": port}
    try:
        ipaddress.ip_address(host)
        result["ip"] = host
    except ValueError:
        result["domain"] = host
    return result


def error_type(message):
    value = message.lower()
    if "unknown user password" in value or "authentication" in value:
        return "authentication_failed"
    if "tls handshake" in value and ("timeout" in value or "deadline exceeded" in value):
        return "tls_handshake_timeout"
    if "bad certificate" in value:
        return "tls_bad_certificate"
    if "unsupported version" in value or "unsupported versions" in value:
        return "tls_unsupported_version"
    if "cipher suite" in value:
        return "tls_unsupported_cipher"
    if "connection reset" in value:
        return "connection_reset"
    if "eof" in value:
        return "unexpected_eof"
    if "bad request" in value or "first record does not look like" in value:
        return "invalid_protocol"
    return "proxy_error"


def base_event(parts, action, outcome):
    event = {
        "@timestamp": timestamp(parts),
        "ecs": {"version": "8.11.0"},
        "event": {
            "kind": "event",
            "category": ["network"],
            "type": ["connection"],
            "action": action,
            "outcome": outcome,
            "provider": "sing-box",
            "dataset": "proxy.access",
        },
        "observer": {
            "name": OBSERVER_NAME,
            "hostname": OBSERVER_HOSTNAME,
            "type": "proxy",
        },
        "service": {"name": "sing-box", "version": SERVICE_VERSION},
        "container": {"name": "passwall-sing-box-1"},
        "proxy": {"connection_id": parts["id"]},
        "log": {"level": parts["level"].lower()},
    }
    duration = elapsed_ns(parts["elapsed"])
    if duration is not None:
        event["event"]["duration"] = duration
    return event


def add_source(event, value):
    ip, port = split_address(value)
    event["source"] = {"ip": ip, "port": port, "address": value}
    event["network"] = {
        "direction": "ingress",
        "type": network_type(ip),
    }


def emit_connect(parts, inbound, source, target, uot=False, handshake=None):
    event = base_event(parts, "proxy-connect", "success")
    event["event"]["type"] = ["start", "connection"]
    add_source(event, source["address"])
    event["user"] = {"name": target["user"]}
    event["destination"] = destination(target["address"])
    transport = "udp" if target.get("packet") or uot else "tcp"
    event["network"]["transport"] = transport
    if event["destination"].get("port") == 53:
        event["network"]["protocol"] = "dns"
    event["proxy"].update(
        {
            "protocol": inbound["protocol"],
            "inbound_tag": inbound["tag"],
            "outbound_tag": "direct",
            "uot": uot,
            "udp_mode": "uot" if uot else ("native" if transport == "udp" else None),
        }
    )
    if event["proxy"]["udp_mode"] is None:
        del event["proxy"]["udp_mode"]
    if handshake:
        event["proxy"]["uot_handshake_address"] = handshake
    return event


def emit_failure(parts, inbound, address, message):
    event = base_event(parts, "proxy-failure", "failure")
    add_source(event, address)
    event["proxy"].update(
        {"protocol": inbound["protocol"], "inbound_tag": inbound["tag"]}
    )
    event["error"] = {"type": error_type(message), "message": message}
    return event


def emit_fallback(parts, inbound, source, target):
    event = base_event(parts, "proxy-fallback", "success")
    add_source(event, source["address"])
    event["network"]["transport"] = "tcp"
    event["proxy"].update(
        {
            "protocol": inbound["protocol"],
            "inbound_tag": inbound["tag"],
            "fallback": True,
            "fallback_target": target,
        }
    )
    return event


auth = base64.b64encode(f"{ES_USER}:{ES_PASSWORD}".encode()).decode()
ssl_context = ssl.create_default_context()
if os.getenv("ES_SSL_VERIFY", "false").lower() != "true":
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE


def send(event):
    request = urllib.request.Request(
        f"{ES_URL}/proxy-access-v3/_doc?op_type=create&pipeline=proxy-access-v3",
        data=json.dumps(event, separators=(",", ":")).encode(),
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, context=ssl_context, timeout=10) as response:
        if response.status not in (200, 201):
            raise RuntimeError(f"Elasticsearch returned {response.status}")


while not os.path.exists(LOG):
    time.sleep(0.2)

states = {}
pending = []
with open(LOG, "r", encoding="utf-8", errors="replace") as log:
    log.seek(0, os.SEEK_END)
    while True:
        if pending:
            try:
                send(pending[0])
                pending.pop(0)
            except Exception as exc:
                print(f"Elasticsearch send failed: {exc}", flush=True)
                time.sleep(2)
                continue

        line = log.readline()
        if not line:
            if log.tell() >= MAX_LOG_BYTES and os.path.getsize(LOG) >= MAX_LOG_BYTES:
                shutil.copyfile(LOG, LOG + ".1")
                with open(LOG, "r+", encoding="utf-8") as active:
                    active.truncate(0)
                log.seek(0)
            cutoff = time.monotonic() - STATE_TTL
            states = {key: value for key, value in states.items() if value["seen"] >= cutoff}
            time.sleep(0.1)
            continue

        original = line.strip()
        match = LINE.match(original)
        if not match:
            continue
        parts = match.groupdict()
        inbound_match = INBOUND.match(parts["component"])
        state = states.setdefault(parts["id"], {"seen": time.monotonic()})
        state["seen"] = time.monotonic()
        if inbound_match:
            state["inbound"] = inbound_match.groupdict()
        inbound = state.get("inbound")
        if not inbound:
            continue

        message = parts["message"]
        source_match = SOURCE.match(message)
        if source_match:
            state["source"] = source_match.groupdict()
            continue

        failure_match = FAILURE.match(message)
        if failure_match:
            event = emit_failure(parts, inbound, failure_match["address"], failure_match["error"])
            event["log"]["original"] = original
            pending.append(event)
            states.pop(parts["id"], None)
            continue

        fallback_match = FALLBACK.match(message)
        if fallback_match and state.get("source"):
            pending.append(emit_fallback(parts, inbound, state["source"], fallback_match["target"]))
            states.pop(parts["id"], None)
            continue

        target_match = TARGET.match(message)
        if target_match:
            target = target_match.groupdict()
            if target["address"] in ("sp.v2.udp-over-tcp.arpa:0", "0.0.0.0:0"):
                state["pending_target"] = target
                continue
            if state.get("source"):
                pending.append(emit_connect(parts, inbound, state["source"], target))
                states.pop(parts["id"], None)
            continue

        uot_match = UOT_TARGET.match(message)
        if uot_match and state.get("source") and state.get("pending_target"):
            target = dict(state["pending_target"])
            target["address"] = uot_match["address"]
            pending.append(
                emit_connect(
                    parts,
                    inbound,
                    state["source"],
                    target,
                    uot=True,
                    handshake=state["pending_target"]["address"],
                )
            )
            states.pop(parts["id"], None)
