#!/bin/sh
set -eu
exec python3 "$(dirname "$0")/server_deploy.py" "$@"
