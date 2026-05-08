#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional


TIME_FIELD_NAMES = {
    "time",
    "timestamp",
    "createtime",
    "msgtime",
    "updatetime",
    "date",
}

EPOCH_13_RE = re.compile(r"(?<!\d)(\d{13})(?!\d)")
EPOCH_10_RE = re.compile(r"(?<!\d)(\d{10})(?!\d)")
DATE_RE = re.compile(
    r"(?<!\d)(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?(?!\d)"
)
ISO_RE = re.compile(
    r"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b"
)

LOCAL_TZ = datetime.now().astimezone().tzinfo or timezone.utc
MIN_EPOCH = int(datetime(2000, 1, 1, tzinfo=timezone.utc).timestamp())


def env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = int(raw)
        return value if value > 0 else default
    except ValueError:
        return default


def env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on", "y"}


def load_redis_config(setting_path: str) -> Dict[str, Any]:
    with open(setting_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    redis_cfg = data.get("redisConfig")
    if not isinstance(redis_cfg, dict):
        raise ValueError("assets/setting.json missing redisConfig")
    return redis_cfg


def build_redis_cli_base_args(redis_cfg: Dict[str, Any]) -> List[str]:
    host = str(redis_cfg.get("Host", "127.0.0.1"))
    port = str(redis_cfg.get("Port", 6379))
    db = str(redis_cfg.get("Db", 0))
    user = str(redis_cfg.get("User", "")).strip()
    passwd = str(redis_cfg.get("Pass", "")).strip()

    args = ["redis-cli", "--raw", "-h", host, "-p", port, "-n", db]
    if user:
        args.extend(["--user", user])
    if passwd:
        args.extend(["-a", passwd])
    return args


def run_redis_cmd(base_args: List[str], *cmd: str) -> str:
    proc = subprocess.run(
        [*base_args, *cmd],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "redis-cli command failed: cmd={!r}, stderr={!r}".format(
                " ".join(cmd), proc.stderr.strip()
            )
        )
    return proc.stdout.rstrip("\n")


def normalize_epoch(raw: float, now_epoch: int) -> Optional[int]:
    # Supports both seconds and milliseconds Unix timestamps.
    sec = int(raw / 1000) if raw > 10**12 else int(raw)
    max_epoch = now_epoch + 10 * 365 * 24 * 3600
    if sec < MIN_EPOCH or sec > max_epoch:
        return None
    return sec


def extract_timestamps_from_text(text: str, now_epoch: int) -> List[int]:
    if not text:
        return []

    payload = text if len(text) <= 200000 else text[:200000]
    candidates: List[int] = []

    for match in EPOCH_13_RE.finditer(payload):
        ts = normalize_epoch(float(match.group(1)), now_epoch)
        if ts is not None:
            candidates.append(ts)

    for match in EPOCH_10_RE.finditer(payload):
        ts = normalize_epoch(float(match.group(1)), now_epoch)
        if ts is not None:
            candidates.append(ts)

    for match in DATE_RE.finditer(payload):
        year = int(match.group(1))
        month = int(match.group(2))
        day = int(match.group(3))
        hour = int(match.group(4) or 0)
        minute = int(match.group(5) or 0)
        second = int(match.group(6) or 0)
        try:
            dt = datetime(year, month, day, hour, minute, second, tzinfo=LOCAL_TZ)
        except ValueError:
            continue
        ts = normalize_epoch(dt.timestamp(), now_epoch)
        if ts is not None:
            candidates.append(ts)

    for token in ISO_RE.findall(payload):
        try:
            dt = datetime.fromisoformat(token.replace("Z", "+00:00"))
        except ValueError:
            continue
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=LOCAL_TZ)
        ts = normalize_epoch(dt.timestamp(), now_epoch)
        if ts is not None:
            candidates.append(ts)

    return candidates


def extract_timestamps_from_scalar(value: Any, now_epoch: int) -> List[int]:
    if isinstance(value, bool) or value is None:
        return []
    if isinstance(value, (int, float)):
        ts = normalize_epoch(float(value), now_epoch)
        return [ts] if ts is not None else []
    if isinstance(value, str):
        return extract_timestamps_from_text(value, now_epoch)
    return []


def extract_timestamps_from_json(node: Any, now_epoch: int) -> List[int]:
    timestamps: List[int] = []
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(key, str) and key.lower() in TIME_FIELD_NAMES:
                timestamps.extend(extract_timestamps_from_scalar(value, now_epoch))
            timestamps.extend(extract_timestamps_from_json(value, now_epoch))
    elif isinstance(node, list):
        for item in node:
            timestamps.extend(extract_timestamps_from_json(item, now_epoch))
    return timestamps


def extract_from_string_payload(payload: str, now_epoch: int) -> List[int]:
    timestamps = extract_timestamps_from_text(payload, now_epoch)
    stripped = payload.strip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            return timestamps
        timestamps.extend(extract_timestamps_from_json(parsed, now_epoch))
    return timestamps


def get_key_type(base_args: List[str], key: str) -> str:
    return run_redis_cmd(base_args, "TYPE", key).strip().lower()


def extract_timestamps_for_key(
    base_args: List[str], key: str, key_type: str, now_epoch: int
) -> List[int]:
    timestamps: List[int] = []
    timestamps.extend(extract_timestamps_from_text(key, now_epoch))

    if key_type == "string":
        val = run_redis_cmd(base_args, "GET", key)
        timestamps.extend(extract_from_string_payload(val, now_epoch))
    elif key_type == "list":
        val = run_redis_cmd(base_args, "LINDEX", key, "0")
        timestamps.extend(extract_from_string_payload(val, now_epoch))
    elif key_type == "hash":
        raw = run_redis_cmd(base_args, "HGETALL", key)
        if raw:
            lines = raw.splitlines()
            for idx in range(1, len(lines), 2):
                timestamps.extend(extract_from_string_payload(lines[idx], now_epoch))
    elif key_type == "zset":
        raw = run_redis_cmd(base_args, "ZREVRANGE", key, "0", "0", "WITHSCORES")
        lines = raw.splitlines()
        if len(lines) >= 2:
            try:
                score = float(lines[1].strip())
            except ValueError:
                score = None
            if score is not None:
                ts = normalize_epoch(score, now_epoch)
                if ts is not None:
                    timestamps.append(ts)

    return timestamps


def scan_keys(base_args: List[str], scan_count: int) -> List[str]:
    all_keys: List[str] = []
    cursor = "0"
    while True:
        output = run_redis_cmd(base_args, "SCAN", cursor, "COUNT", str(scan_count))
        lines = output.splitlines() if output else ["0"]
        cursor = lines[0].strip() if lines else "0"
        if len(lines) > 1:
            all_keys.extend([line for line in lines[1:] if line != ""])
        if cursor == "0":
            break
    return all_keys


def main() -> int:
    started_at = datetime.now(timezone.utc)
    now_epoch = int(started_at.timestamp())

    setting_path = os.getenv("IWECHAT_SETTING_PATH", "/app/assets/setting.json")
    cutoff_days = env_int("REDIS_GC_CUTOFF_DAYS", 3)
    scan_count = env_int("REDIS_GC_SCAN_COUNT", 1000)
    fallback_flushdb = env_bool("REDIS_GC_FALLBACK_FLUSHDB", True)

    cutoff_epoch = int((started_at - timedelta(days=cutoff_days)).timestamp())

    result: Dict[str, Any] = {
        "component": "redis_gc",
        "started_at": started_at.isoformat(),
        "setting_path": setting_path,
        "cutoff_days": cutoff_days,
        "cutoff_epoch": cutoff_epoch,
        "scan_count": scan_count,
        "fallback_flushdb_enabled": fallback_flushdb,
        "scanned_keys": 0,
        "classified_keys": 0,
        "deleted_keys": 0,
        "fallback_flushdb_triggered": False,
        "errors": 0,
    }

    try:
        redis_cfg = load_redis_config(setting_path)
        base_args = build_redis_cli_base_args(redis_cfg)
        keys = scan_keys(base_args, scan_count)
        result["scanned_keys"] = len(keys)

        for key in keys:
            try:
                key_type = get_key_type(base_args, key)
                if key_type in {"none"}:
                    continue
                timestamps = extract_timestamps_for_key(base_args, key, key_type, now_epoch)
                if not timestamps:
                    continue

                result["classified_keys"] += 1
                latest_ts = max(timestamps)
                if latest_ts < cutoff_epoch:
                    deleted_count_raw = run_redis_cmd(base_args, "DEL", key).strip()
                    try:
                        deleted_count = int(deleted_count_raw or "0")
                    except ValueError:
                        deleted_count = 0
                    result["deleted_keys"] += deleted_count
            except Exception:
                result["errors"] += 1

        if result["classified_keys"] == 0 and fallback_flushdb:
            run_redis_cmd(base_args, "FLUSHDB")
            result["fallback_flushdb_triggered"] = True

        result["finished_at"] = datetime.now(timezone.utc).isoformat()
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:
        result["status"] = "error"
        result["error"] = str(exc)
        result["finished_at"] = datetime.now(timezone.utc).isoformat()
        print(json.dumps(result, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
