#!/usr/bin/env bash
set -u

initial_delay="${REDIS_GC_INITIAL_DELAY_SECONDS:-120}"
interval_seconds="${REDIS_GC_INTERVAL_SECONDS:-259200}"
gc_script_path="${REDIS_GC_SCRIPT_PATH:-/app/scripts/redis_gc.py}"

echo "[redis_gc_loop] initial_delay=${initial_delay}s interval=${interval_seconds}s script=${gc_script_path}"
sleep "${initial_delay}"

while true; do
  echo "[redis_gc_loop] running redis gc at $(date '+%Y-%m-%d %H:%M:%S %z')"
  if ! python3 "${gc_script_path}"; then
    echo "[redis_gc_loop] redis gc failed at $(date '+%Y-%m-%d %H:%M:%S %z')"
  fi
  sleep "${interval_seconds}"
done
