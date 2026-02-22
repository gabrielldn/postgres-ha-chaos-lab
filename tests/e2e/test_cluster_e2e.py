from __future__ import annotations

import os
import time

import psycopg
import pytest

NODES = ("pg1", "pg2", "pg3")
PG_USER = os.getenv("PG_SUPERUSER", "postgres")
PG_PASS = os.getenv("PG_SUPERPASS", "dummy-superpass-change-me")
PG_DB = os.getenv("PG_APP_DB", "appdb")


def _query(host: str, port: int, sql: str, dbname: str | None = None) -> list[tuple]:
    with psycopg.connect(
        host=host,
        port=port,
        user=PG_USER,
        password=PG_PASS,
        dbname=dbname or PG_DB,
        connect_timeout=2,
    ) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            if cur.description:
                return cur.fetchall()
            conn.commit()
            return []


def _discover_node_roles() -> dict[str, bool]:
    roles: dict[str, bool] = {}
    for node in NODES:
        try:
            row = _query(node, 5432, "SELECT pg_is_in_recovery()", dbname="postgres")
        except Exception:
            continue
        if row:
            roles[node] = bool(row[0][0])
    return roles


@pytest.mark.e2e
def test_cluster_has_single_leader(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    deadline = time.time() + 60
    last_roles: dict[str, bool] = {}
    while time.time() < deadline:
        roles = _discover_node_roles()
        if len(roles) == len(NODES):
            leaders = [node for node, is_replica in roles.items() if not is_replica]
            replicas = [node for node, is_replica in roles.items() if is_replica]
            if len(leaders) == 1 and len(replicas) >= 1:
                return
        last_roles = roles
        time.sleep(2)

    pytest.fail(f"cluster sem 1 lider + replicas dentro do timeout. ultimo estado: {last_roles}")


@pytest.mark.e2e
def test_rw_endpoint_accepts_write(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    _query(
        "haproxy",
        5432,
        "CREATE TABLE IF NOT EXISTS e2e_rw (id bigserial primary key, created_at timestamptz default now())",
    )
    rows = _query("haproxy", 5432, "INSERT INTO e2e_rw DEFAULT VALUES RETURNING id")
    assert rows and rows[0][0] is not None


@pytest.mark.e2e
def test_ro_endpoint_accepts_read(stack_running: bool) -> None:
    if not stack_running:
        pytest.skip("stack nao esta ativa")

    deadline = time.time() + 40
    last_error = "sem resposta do endpoint RO"
    while time.time() < deadline:
        try:
            rows = _query("haproxy", 5433, "SELECT inet_server_addr()::text, pg_is_in_recovery()")
            if rows and rows[0][0] and bool(rows[0][1]):
                return
            last_error = f"RO roteou para primario ou sem endereco: {rows!r}"
        except Exception as exc:
            last_error = str(exc)
            time.sleep(2)

    pytest.fail(f"endpoint RO nao estabilizou em replica dentro do timeout: {last_error}")
