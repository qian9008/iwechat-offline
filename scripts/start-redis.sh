#!/usr/bin/env bash
set -euo pipefail

# Remove persisted data to avoid recovering stale cache after container restarts.
rm -f /var/lib/redis/dump.rdb /var/lib/redis/appendonly.aof
rm -f /data/dump.rdb /data/appendonly.aof
rm -rf /var/lib/redis/appendonlydir /data/appendonlydir

mkdir -p /dev/shm/redis

exec /usr/bin/redis-server --save "" --appendonly no --dir /dev/shm/redis
