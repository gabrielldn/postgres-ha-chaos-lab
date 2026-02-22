from __future__ import annotations

import json
import os
import subprocess
import time

import psycopg
import pytest

from conftest import compose_cmd


def _exec_pg1_patronictl() -> list[dict]:
    proc = subprocess.run(
        compose_cmd("exec", "-T", "pg1", "patronictl", "-c", "/etc/patroni/patroni.yml", "list", "-f", "json"),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(proc.stdout)


def _query(sql: str, port: int) -> list[tuple]:
    pg_user = os.getenv("PG_SUPERUSER", "postgres")
    pg_pass = os.getenv("PG_SUPERPASS", "dummy-superpass-change-me")
    pg_db = os.getenv("PG_APP_DB", "appdb")

    with psycopg.connect(
        host="haproxy",
        port=port,
        user=pg_user,
        password=pg_pass,
        dbname=pg_db,
        connect_timeout=2,
    ) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            if cur.description:
                return cur.fetchall()
            conn.commit()
            return []


@pytest.mark.e2e
def test_cluster_has_single_leader(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    members = _exec_pg1_patronictl()
    leaders = [m for m in members if m.get("Role") == "Leader"]
    replicas = [m for m in members if m.get("Role") == "Replica"]

    assert len(leaders) == 1, members
    assert len(replicas) >= 1, members


@pytest.mark.e2e
def test_rw_endpoint_accepts_write(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    _query(
        "CREATE TABLE IF NOT EXISTS e2e_rw (id bigserial primary key, created_at timestamptz default now())",
        5432,
    )
    rows = _query("INSERT INTO e2e_rw DEFAULT VALUES RETURNING id", 5432)
    assert rows and rows[0][0] is not None


@pytest.mark.e2e
def test_ro_endpoint_accepts_read(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    deadline = time.time() + 40
    while time.time() < deadline:
        try:
            rows = _query("SELECT inet_server_addr()::text", 5433)
            assert rows and rows[0][0]
            return
        except Exception:
            time.sleep(2)

    pytest.fail("endpoint RO nao respondeu dentro do timeout")
