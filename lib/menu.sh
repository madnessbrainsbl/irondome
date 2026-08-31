#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

menu_choice() {
  local choice
  while true; do
    printf '\n'
    printf '  [1] Setup wizard (first run)\n'
    printf '  [2] Render configuration\n'
    printf '  [3] Install services (sudo)\n'
    printf '  [4] Start strict mode (sudo)\n'
    printf '  [5] Status\n'
    printf '  [6] Doctor (leak checks)\n'
    printf '  [7] Stop stack (sudo)\n'
    printf '  [8] Help\n'
    printf '  [0] Quit\n'
    read -r -p 'Select [0-8]: ' choice
    case "$choice" in
      "") printf 'quit\n'; return ;;
      0|q) printf 'quit\n'; return ;;
      1) printf 'setup\n'; return ;;
      2) printf 'render\n'; return ;;
      3) printf 'install\n'; return ;;
      4) printf 'start\n'; return ;;
      5) printf 'status\n'; return ;;
      6) printf 'doctor\n'; return ;;
      7) printf 'stop\n'; return ;;
      8) printf 'help\n'; return ;;
      *) printf 'Invalid choice: %s\n' "$choice" >&2 ;;
    esac
  done
}

irondome_menu() {
  local action
  while true; do
    irondome_banner
    printf '  Interactive menu - pick an action.\n'
    action="$(menu_choice)"
    case "$action" in
      quit) printf '\nGoodbye.\n'; exit 0 ;;
      setup) "$LIB_DIR/setup.sh" ;;
      render) "$LIB_DIR/render.sh" ;;
      install) "$LIB_DIR/install.sh" ;;
      start) "$LIB_DIR/start.sh" ;;
      status) "$LIB_DIR/status.sh" ;;
      doctor) "$LIB_DIR/doctor.sh" ;;
      stop) "$LIB_DIR/stop.sh" ;;
      help) irondome_help ;;
    esac
  done
}

irondome_menu
