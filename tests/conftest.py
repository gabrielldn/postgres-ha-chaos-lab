from __future__ import annotations

import socket
import time

import pytest

def _is_port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session")
def stack_running() -> bool:
    deadline = time.time() + 45
    while time.time() < deadline:
        if _is_port_open("haproxy", 5432) and any(_is_port_open(node, 5432) for node in ("pg1", "pg2", "pg3")):
            return True
        time.sleep(1)
    return False
