#!/bin/sh
set -eu

# Railway mounts volumes as root. Make the mount point writable by the
# unprivileged application user without recursively walking user projects.
mkdir -p /workspace /workspace/.codebuddy
chown codebuddy:codebuddy /workspace /workspace/.codebuddy

exec gosu codebuddy "$@"
