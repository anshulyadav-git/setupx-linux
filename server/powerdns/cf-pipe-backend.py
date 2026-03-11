#!/usr/bin/env python3
"""
PowerDNS pipe backend — serves DNS answers from Cloudflare API.
Records are cached for 30 s to avoid hitting the CF rate limit.
"""
import sys
import os
import time
import json
import urllib.request

CF_TOKEN = os.environ.get("CF_TOKEN", "")
CF_ZONE  = os.environ.get("CF_ZONE", "")
DOMAIN   = os.environ.get("CF_DOMAIN", "r-u.live")
CACHE_TTL = 30

_cache: dict = {}
_cache_ts: float = 0


def log(msg: str) -> None:
    import sys as _sys
    print(f"LOG\t{msg}", flush=True)
    print(f"DEBUG: {msg}", file=_sys.stderr, flush=True)


def fetch_records() -> list:
    global _cache, _cache_ts
    now = time.time()
    if now - _cache_ts < CACHE_TTL and _cache:
        return list(_cache.values())

    url = f"https://api.cloudflare.com/client/v4/zones/{CF_ZONE}/dns_records?per_page=100"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {CF_TOKEN}", "Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.load(r)
        records = data.get("result", [])
        _cache = {r["id"]: r for r in records}
        _cache_ts = now
        return records
    except Exception as e:
        log(f"CF API error: {e}")
        return list(_cache.values())


SOA_RECORD = (
    f"ns1.{DOMAIN} hostmaster.{DOMAIN} "
    "2024031101 3600 900 604800 300"
)


def answer(qname: str, qtype: str) -> list:
    qname = qname.rstrip(".").lower()
    results = []

    # Synthetic SOA — required for PowerDNS to consider itself authoritative
    if qtype in ("SOA", "ANY") and qname == DOMAIN:
        results.append(f"DATA\t{qname}\tIN\tSOA\t300\t1\t{SOA_RECORD}")

    # Synthetic NS records if not in Cloudflare
    if qtype in ("NS", "ANY") and qname == DOMAIN:
        has_ns = any(
            r["type"] == "NS" and r["name"].lower() == DOMAIN
            for r in fetch_records()
        )
        if not has_ns:
            results.append(f"DATA\t{qname}\tIN\tNS\t300\t1\tns1.{DOMAIN}.")
            results.append(f"DATA\t{qname}\tIN\tNS\t300\t1\tns2.{DOMAIN}.")

    if qtype == "SOA":
        return results

    for r in fetch_records():
        name = r["name"].lower()
        rtype = r["type"]
        content = r["content"]
        ttl = r.get("ttl", 300)
        if ttl == 1:
            ttl = 300  # CF auto TTL → 300

        if name != qname:
            continue

        if qtype not in ("ANY", rtype):
            continue

        if rtype == "A":
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}")
        elif rtype == "AAAA":
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}")
        elif rtype == "CNAME":
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}.")
        elif rtype == "MX":
            prio = r.get("priority", 10)
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{prio}\t{content}.")
        elif rtype == "TXT":
            # CF API already wraps TXT content in quotes: '"v=spf1 ..."'
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}")
        elif rtype == "NS":
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}.")
        elif rtype == "SRV":
            results.append(f"DATA\t{qname}\tIN\t{rtype}\t{ttl}\t1\t{content}")

    return results


def handle_lookup(parts: list) -> None:
    # Q\tqname\tqclass\tqtype\tid\tremote-ip\tlocal-ip\treal-remote
    if len(parts) < 5:
        print("FAIL", flush=True)
        return
    qname = parts[1]
    qtype = parts[3]
    try:
        rows = answer(qname, qtype)
        for row in rows:
            print(row, flush=True)
        print("END", flush=True)
    except Exception as e:
        log(f"EXCEPTION in answer({qname!r}, {qtype!r}): {e}")
        print("FAIL", flush=True)


def main() -> None:
    # Handshake
    line = sys.stdin.readline().strip()
    if not line.startswith("HELO"):
        sys.exit(1)
    print("OK\tCF pipe backend ready", flush=True)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        parts = line.split("\t")
        cmd = parts[0]
        if cmd == "Q":
            handle_lookup(parts)
        elif cmd == "AXFR":
            print("END", flush=True)
        elif cmd == "PING":
            print("END", flush=True)
        else:
            log(f"Unknown command: {line!r}")
            print("FAIL", flush=True)


if __name__ == "__main__":
    main()
