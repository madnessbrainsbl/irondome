#!/bin/bash
set -euo pipefail

echo "This is a template only."
echo "Expected stop sequence: lock -> transparent route -> cliproxy -> google-forward -> privoxy -> outline -> tor"
