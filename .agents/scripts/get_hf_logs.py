#!/usr/bin/env python3
"""
CLI Script to fetch and stream runtime / build logs from a Hugging Face Space.
Complies with AGENTS.md guidelines (zero external bloat, surgical implementation).

Usage:
    python3 .agents/scripts/get_hf_logs.py [--lines 100] [--build] [--follow] [--raw]
"""

import os
import sys
import json
import re
import argparse
import signal
import time
from collections import deque
from pathlib import Path

# Optional color output for terminal
IS_TTY = sys.stdout.isatty()
CLR_RESET = "\033[0m" if IS_TTY else ""
CLR_BOLD = "\033[1m" if IS_TTY else ""
CLR_RED = "\033[91m" if IS_TTY else ""
CLR_GREEN = "\033[92m" if IS_TTY else ""
CLR_YELLOW = "\033[93m" if IS_TTY else ""
CLR_CYAN = "\033[96m" if IS_TTY else ""
CLR_DIM = "\033[2m" if IS_TTY else ""

DEFAULT_SPACE_ID = "Nguyenvananan2005/saman-backend"


def print_info(msg: str):
    print(f"{CLR_CYAN}[*]{CLR_RESET} {msg}", file=sys.stderr)


def print_success(msg: str):
    print(f"{CLR_GREEN}[✓]{CLR_RESET} {msg}", file=sys.stderr)


def print_warning(msg: str):
    print(f"{CLR_YELLOW}[!]{CLR_RESET} {msg}", file=sys.stderr)


def print_error(msg: str):
    print(f"{CLR_RED}[✗] {msg}{CLR_RESET}", file=sys.stderr)


def find_hf_token(cli_token: str | None = None) -> str | None:
    """
    Resolve Hugging Face Access Token with priority:
    1. CLI argument (--token)
    2. os.environ["HF_TOKEN"]
    3. .env or backend/.env files
    """
    if cli_token and cli_token.strip():
        return cli_token.strip()

    # Check environment variable
    env_token = os.environ.get("HF_TOKEN")
    if env_token and env_token.strip():
        return env_token.strip()

    # Search candidate .env paths
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    cwd = Path.cwd()

    candidates = [
        cwd / ".env",
        cwd / "backend" / ".env",
        repo_root / ".env",
        repo_root / "backend" / ".env",
    ]

    seen = set()
    for env_path in candidates:
        try:
            resolved = env_path.resolve()
            if resolved in seen or not resolved.is_file():
                continue
            seen.add(resolved)

            for line in resolved.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, val = line.split("=", 1)
                if key.strip() == "HF_TOKEN":
                    token = val.strip().strip("'\"")
                    if token:
                        return token
        except Exception:
            continue

    return None


def get_space_status(space_id: str, token: str | None = None) -> dict:
    """Fetch space metadata including runtime stage."""
    url = f"https://huggingface.co/api/spaces/{space_id}"
    headers = {"User-Agent": "HF-Logs-CLI/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    try:
        import requests
        r = requests.get(url, headers=headers, timeout=10)
        if r.status_code == 200:
            return r.json()
    except Exception:
        import urllib.request
        import ssl
        try:
            ctx = ssl.create_default_context()
        except Exception:
            ctx = None
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
                if resp.status == 200:
                    return json.loads(resp.read().decode("utf-8"))
        except Exception:
            pass
    return {}


def get_space_jwt(space_id: str, token: str) -> str:
    """Retrieve Space JWT using Hugging Face user access token."""
    url = f"https://huggingface.co/api/spaces/{space_id}/jwt"
    headers = {
        "Authorization": f"Bearer {token}",
        "User-Agent": "HF-Logs-CLI/1.0",
    }

    try:
        import requests
        r = requests.get(url, headers=headers, timeout=15)
        if r.status_code == 200:
            data = r.json()
            jwt = data.get("token") or data.get("accessToken")
            if jwt:
                return jwt
            raise RuntimeError(f"JWT not found in response: {r.text[:100]}")
        elif r.status_code == 401:
            raise PermissionError("401 Unauthorized: HF_TOKEN is invalid or lacks Read permission.")
        elif r.status_code == 404:
            raise FileNotFoundError(f"404 Not Found: Space '{space_id}' does not exist.")
        else:
            raise RuntimeError(f"Failed to get JWT (HTTP {r.status_code}): {r.text[:200]}")
    except (ImportError, requests.exceptions.RequestException) as e:
        if isinstance(e, (PermissionError, FileNotFoundError, RuntimeError)):
            raise

        # Fallback to urllib
        import urllib.request
        import urllib.error
        import ssl
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except Exception:
            ctx = ssl.create_default_context()

        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                jwt = data.get("token") or data.get("accessToken")
                if jwt:
                    return jwt
                raise RuntimeError(f"JWT not found in response.")
        except urllib.error.HTTPError as he:
            if he.code == 401:
                raise PermissionError("401 Unauthorized: HF_TOKEN is invalid or lacks Read permission.")
            elif he.code == 404:
                raise FileNotFoundError(f"404 Not Found: Space '{space_id}' does not exist.")
            raise RuntimeError(f"HTTP Error {he.code}: {he.read().decode('utf-8', errors='ignore')[:200]}")


def is_noise_line(line: str) -> bool:
    """
    Filter noise lines (repetitive health checks, empty prompts)
    while preserving tracebacks, errors, and application logs.
    """
    stripped = line.strip()
    if not stripped:
        return True

    # Always preserve errors, tracebacks, and warnings
    if any(kw in stripped for kw in [
        "Traceback", "Error", "ERROR", "Exception", "Failed",
        "CRITICAL", "Warning", "WARNING", "[Startup]", "[Router]"
    ]):
        return False

    # Filter out repetitive HF health checks or ping probes
    if re.search(r'\"GET /(health|api/food/health)? HTTP/1\.[01]\"\s+200', stripped):
        return True

    # Filter carriage return artifact progress
    if stripped.startswith("[") and ("=====" in stripped or "--:--" in stripped):
        return True

    return False


def format_log_line(raw_text: str, timestamp: str | None, show_timestamps: bool) -> str:
    """Format and colorize log line according to log level."""
    prefix = ""
    if show_timestamps and timestamp:
        prefix = f"{CLR_DIM}[{timestamp[:19].replace('T', ' ')}]{CLR_RESET} "

    # Highlight error lines
    if "ERROR" in raw_text or "Traceback" in raw_text or "Exception" in raw_text:
        return f"{prefix}{CLR_RED}{raw_text}{CLR_RESET}"
    if "WARNING" in raw_text or "WARN" in raw_text:
        return f"{prefix}{CLR_YELLOW}{raw_text}{CLR_RESET}"
    if "INFO" in raw_text:
        return f"{prefix}{raw_text}"
    return f"{prefix}{raw_text}"


def stream_logs(
    space_id: str,
    jwt_token: str,
    hf_token: str,
    log_type: str = "run",
    max_lines: int = 100,
    follow: bool = False,
    raw_mode: bool = False,
    show_timestamps: bool = False,
):
    """
    Stream and print logs from Hugging Face Space.
    Connects to https://api.hf.space/v1/{space_id}/logs/{log_type}
    Fallback to https://huggingface.co/api/spaces/{space_id}/logs/{log_type}
    """
    urls_to_try = [
        (f"https://api.hf.space/v1/{space_id}/logs/{log_type}", {"Authorization": f"Bearer {jwt_token}"}),
        (f"https://huggingface.co/api/spaces/{space_id}/logs/{log_type}", {"Authorization": f"Bearer {hf_token}"}),
    ]

    import requests

    success = False
    for url, headers in urls_to_try:
        headers["User-Agent"] = "HF-Logs-CLI/1.0"
        headers["Accept"] = "text/event-stream"

        # In non-follow mode, use a short read timeout (3.0s) so after backlog is drained, we exit cleanly.
        # In follow mode, use None or long timeout to stay connected.
        timeout = (10, None if follow else 3.5)

        try:
            with requests.get(url, headers=headers, stream=True, timeout=timeout) as response:
                if response.status_code == 401:
                    continue  # Try next endpoint
                if response.status_code != 200:
                    print_warning(f"Endpoint {url} returned HTTP {response.status_code}")
                    continue

                success = True
                recent_buffer = deque(maxlen=max_lines)

                try:
                    for line in response.iter_lines(decode_unicode=True):
                        if not line:
                            continue
                        if not line.startswith("data:"):
                            continue

                        payload = line[5:].strip()
                        if not payload or payload == "{}":
                            continue

                        try:
                            event = json.loads(payload)
                        except json.JSONDecodeError:
                            continue

                        text_chunk = event.get("data", "")
                        timestamp = event.get("timestamp")

                        for subline in text_chunk.splitlines():
                            if not raw_mode and is_noise_line(subline):
                                continue

                            formatted = format_log_line(subline, timestamp, show_timestamps)
                            if follow:
                                print(formatted)
                                sys.stdout.flush()
                            else:
                                recent_buffer.append(formatted)

                except requests.exceptions.ReadTimeout:
                    # Buffer drained in non-follow mode
                    pass
                except KeyboardInterrupt:
                    print(f"\n{CLR_YELLOW}[*] Streaming stopped by user.{CLR_RESET}", file=sys.stderr)
                    return

                # Flush buffer in non-follow mode
                if not follow:
                    if not recent_buffer:
                        print_info(f"No recent {log_type} logs found or buffer is currently empty.")
                    else:
                        print_info(f"Showing last {len(recent_buffer)} lines of {log_type} logs:")
                        print("-" * 70, file=sys.stderr)
                        for item in recent_buffer:
                            print(item)
                        print("-" * 70, file=sys.stderr)
                return

        except requests.exceptions.RequestException:
            continue

    if not success:
        print_error("Failed to connect to HF logs stream. Verify that your HF_TOKEN has Read permissions.")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Stream and inspect logs from Hugging Face Space.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--lines", "-n",
        type=int,
        default=100,
        help="Number of recent log lines to display (default: 100)",
    )
    parser.add_argument(
        "--type", "-t",
        choices=["run", "build"],
        default="run",
        help="Log stream type to fetch (run or build)",
    )
    parser.add_argument(
        "--build", "-b",
        action="store_true",
        help="Shortcut to fetch build logs instead of run logs",
    )
    parser.add_argument(
        "--follow", "-f",
        action="store_true",
        help="Follow log stream in real time (press Ctrl+C to stop)",
    )
    parser.add_argument(
        "--space", "-s",
        type=str,
        default=DEFAULT_SPACE_ID,
        help="Hugging Face Space ID (namespace/repo_name)",
    )
    parser.add_argument(
        "--token",
        type=str,
        default=None,
        help="Hugging Face Access Token (overrides environment and .env)",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Show raw logs without noise filtering",
    )
    parser.add_argument(
        "--timestamps",
        action="store_true",
        help="Display timestamps for log entries",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Inspect Space status without fetching logs",
    )

    args = parser.parse_args()

    # Graceful exit on SIGINT
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))

    log_type = "build" if args.build else args.type

    # 1. Resolve HF_TOKEN
    token = find_hf_token(args.token)

    # 2. Check Space Status (can inspect public space even before token check)
    if args.status:
        print_info(f"Target Space: {CLR_BOLD}{args.space}{CLR_RESET}")
        space_info = get_space_status(args.space, token)
        runtime = space_info.get("runtime", {})
        stage = runtime.get("stage", "UNKNOWN")
        print_info(f"Space Stage:  {CLR_BOLD}{stage}{CLR_RESET}")
        sys.exit(0)

    if not token:
        print_error("HF_TOKEN was not found in environment variables, .env, or backend/.env!")
        print(f"\n{CLR_YELLOW}Lưu ý:{CLR_RESET}")
        print("  1. Hãy chắc chắn bạn đã nhấn tổ hợp phím Cmd+S (hoặc Ctrl+S) để lưu file backend/.env.")
        print("     Định dạng: HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        print("  2. Hoặc export trong terminal: export HF_TOKEN=\"hf_xxxxxxx\"")
        print("  3. Hoặc truyền trực tiếp: python3 .agents/scripts/get_hf_logs.py --token \"hf_xxxxxxx\"\n")
        sys.exit(1)

    print_info(f"Target Space: {CLR_BOLD}{args.space}{CLR_RESET}")

    space_info = get_space_status(args.space, token)
    runtime = space_info.get("runtime", {})
    stage = runtime.get("stage", "UNKNOWN")
    print_info(f"Space Stage:  {CLR_BOLD}{stage}{CLR_RESET}")

    if args.status:
        sys.exit(0)

    # Suggest build logs if space is in building/error state
    if stage in ["BUILDING", "BUILD_ERROR"] and log_type == "run":
        print_warning(f"Space is currently {stage}. Switching to build logs...")
        log_type = "build"

    # 3. Request Space JWT
    print_info(f"Authenticating and acquiring Space JWT for {log_type} logs...")
    try:
        jwt_token = get_space_jwt(args.space, token)
        print_success("Space JWT acquired successfully.")
    except Exception as e:
        print_error(f"Authentication failed: {e}")
        sys.exit(1)

    # 4. Stream Logs
    print_info(f"Connecting to {log_type} log stream (limit: {args.lines} lines)...")
    stream_logs(
        space_id=args.space,
        jwt_token=jwt_token,
        hf_token=token,
        log_type=log_type,
        max_lines=args.lines,
        follow=args.follow,
        raw_mode=args.raw,
        show_timestamps=args.timestamps,
    )


if __name__ == "__main__":
    main()
