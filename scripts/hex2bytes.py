#!/usr/bin/env python3
"""Convert a hex Zigbee key/identifier into the decimal byte array Zigbee2MQTT wants.

Zigbee2MQTT's config schema requires arrays of numbers for advanced.network_key
(16 bytes) and advanced.ext_pan_id (8 bytes), while ZHA/zigpy backups store
them as hex strings. Separators are irrelevant: "25:60:1c", "25 60 1c",
"0x25601c" and "25601c" all parse the same.

Usage:
    hex2bytes.py 25:60:1c:6f:83:5c:8e:20          # from an argument
    hex2bytes.py -n 16 <<< "$KEY"                 # from stdin, length-checked
    hex2bytes.py -f backup.json -k network_key    # straight out of a ZHA backup
    hex2bytes.py -f backup.json -k ext_pan_id

Reading from the backup with -f avoids putting the network key in your shell
history or in the process list, which `ps` exposes to every local user.
"""

import argparse
import json
import re
import sys

# JSON paths inside a zigpy NetworkBackup (what ZHA's "download backup"
# exports), the byte count Zigbee2MQTT expects, and whether the string must be
# reversed. zigpy prints EUI64-typed values (extended_pan_id) most-significant
# byte first, i.e. reversed from the wire order; keys (KeyData) are printed in
# wire order. zigbee-herdsman compares config.advanced.ext_pan_id byte-for-byte
# against the raw EZSP network parameters (wire order), so a non-reversed
# ext_pan_id makes the ember driver leave the existing network on first start.
# Verified against zigpy 0.86: ExtendedPanId.deserialize(01..08) -> "08:07:..:01".
BACKUP_FIELDS = {
    "network_key": (("network_info", "network_key", "key"), 16, False),
    "ext_pan_id": (("network_info", "extended_pan_id"), 8, True),
    "tc_link_key": (("network_info", "tc_link_key", "key"), 16, False),
}


def hex_to_bytes(text, expected=None):
    """Parse a hex string into a list of ints, rejecting anything malformed."""
    cleaned = re.sub(r"(?i)^0x", "", text.strip().replace(":", "").replace("-", ""))
    cleaned = re.sub(r"\s+", "", cleaned)

    if not cleaned:
        raise ValueError("no hex digits found")
    if re.search(r"[^0-9a-fA-F]", cleaned):
        bad = sorted(set(re.findall(r"[^0-9a-fA-F]", cleaned)))
        raise ValueError(f"non-hex characters present: {''.join(bad)}")
    if len(cleaned) % 2:
        raise ValueError(f"odd number of hex digits ({len(cleaned)}) — not whole bytes")

    values = [int(cleaned[i : i + 2], 16) for i in range(0, len(cleaned), 2)]

    if expected is not None and len(values) != expected:
        raise ValueError(f"expected {expected} bytes, got {len(values)}")
    return values


def from_backup(path, field):
    keys, expected, reverse = BACKUP_FIELDS[field]
    with open(path) as handle:
        node = json.load(handle)
    for key in keys:
        if not isinstance(node, dict) or key not in node:
            raise ValueError(f"{path}: no '{'.'.join(keys)}' — not a coordinator backup?")
        node = node[key]
    return node, expected, reverse


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("hex", nargs="?", help="hex string; omit to read stdin")
    parser.add_argument("-f", "--file", help="read from a ZHA/zigpy backup JSON instead")
    parser.add_argument(
        "-k",
        "--field",
        choices=sorted(BACKUP_FIELDS),
        default="network_key",
        help="which field to pull with --file (default: network_key)",
    )
    parser.add_argument(
        "-n",
        "--bytes",
        type=int,
        help="require exactly this many bytes (16 for a network key, 8 for ext_pan_id)",
    )
    parser.add_argument(
        "-e",
        "--env",
        action="store_true",
        help="emit a ZIGBEE2MQTT_CONFIG_* env-file line rather than a bare array",
    )
    args = parser.parse_args()

    try:
        reverse = False
        if args.file:
            text, expected, reverse = from_backup(args.file, args.field)
            field = args.field
        else:
            text = args.hex if args.hex is not None else sys.stdin.read()
            expected = args.bytes
            field = args.field
        if args.bytes is not None:
            expected = args.bytes
        values = hex_to_bytes(text, expected)
        if reverse:
            values.reverse()
    except (OSError, ValueError, json.JSONDecodeError) as err:
        sys.exit(f"error: {err}")

    array = json.dumps(values)
    if args.env:
        name = {"ext_pan_id": "ADVANCED_EXT_PAN_ID"}.get(field, "ADVANCED_NETWORK_KEY")
        print(f"ZIGBEE2MQTT_CONFIG_{name}={array}")
    else:
        print(array)


if __name__ == "__main__":
    main()
