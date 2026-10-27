#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -r /etc/os-release ]; then
    echo "ERROR: Cannot identify the operating system because /etc/os-release is unavailable."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

rocky_version="${VERSION_ID:-}"
rocky_major="${rocky_version%%.*}"
if [ "${ID:-}" != "rocky" ] || [ "$rocky_major" != "10" ]; then
    echo "ERROR: installation_rocky10.sh requires Rocky Linux 10."
    echo "Detected: ${PRETTY_NAME:-unknown operating system}"
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "ERROR: This installer currently supports Rocky Linux 10 on x86_64 only."
    echo "Detected architecture: $(uname -m)"
    exit 1
fi

export WRF_INSTALL_OS_PROFILE=rocky10

cd "$SCRIPT_DIR"
exec bash "$SCRIPT_DIR/installation.sh" "$@"
