#!/bin/bash
set -euo pipefail

TORRC="__PROJECT_ROOT__/templates/torrc.strict"

echo "Paste obfs4 bridges, one per line. Empty line ends input."
BRIDGES=""
while IFS= read -r line; do
  [[ -z "$line" ]] && break
  BRIDGES+="${line}"$'\n'
done

[[ -z "$BRIDGES" ]] && { echo "No bridges provided."; exit 1; }

sed -i '/^UseBridges /d;/^ClientTransportPlugin /d;/^Bridge /d' "$TORRC"

{
  echo "UseBridges 1"
  echo "ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy"
  while IFS= read -r b; do
    [[ -z "$b" ]] && continue
    [[ "$b" =~ ^Bridge[[:space:]] ]] || b="Bridge $b"
    echo "$b"
  done <<< "$BRIDGES"
} >> "$TORRC"
