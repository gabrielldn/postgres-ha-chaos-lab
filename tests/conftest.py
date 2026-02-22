from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
ENV_EXAMPLE = ROOT / ".env.example"
LOCK_FILE = ROOT / "compose" / "images.lock.env"
COMPOSE_FILE = ROOT / "compose" / "docker-compose.yml"


def compose_cmd(*args: str) -> list[str]:
    env = ENV_FILE if ENV_FILE.exists() else ENV_EXAMPLE
    return [
        "docker",
        "compose",
        "--env-file",
        str(env),
        "--env-file",
        str(LOCK_FILE),
        "-f",
        str(COMPOSE_FILE),
        *args,
    ]


def run_cmd(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(args), cwd=ROOT, text=True, capture_output=True, check=check)


@pytest.fixture(scope="session")
def stack_running() -> bool:
    proc = subprocess.run(
        compose_cmd("ps", "--services", "--filter", "status=running"),
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    return proc.returncode == 0 and "pg" in proc.stdout
