#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/cluster.sh"

primary="$(wait_for_primary 120)"
if [[ -z "${primary}" ]]; then
  echo "Cluster sem primario para inicializacao" >&2
  exit 1
fi

patroni_admin_node="pg1"
if ! compose_base ps --status running --services | grep -qx "pg1"; then
  patroni_admin_node="${primary}"
fi

# Garante tuning de failover mesmo quando o cluster ja existia com valores antigos no DCS.
compose_base exec -T "${patroni_admin_node}" patronictl -c /etc/patroni/patroni.yml edit-config \
  --set ttl=10 \
  --set loop_wait=2 \
  --set retry_timeout=3 \
  --force >/dev/null

"${ROOT_DIR}/pgbackrest/scripts/stanza-create.sh"

deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  if compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' psql -v ON_ERROR_STOP=1 -h haproxy -p 5432 -U '${PG_SUPERUSER}' -d postgres -Atqc \"SELECT 1;\"" \
    >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if (( SECONDS >= deadline )); then
  echo "Timeout aguardando endpoint RW no HAProxy" >&2
  exit 1
fi

compose_base exec -T psql-client bash -lc \
  "PGPASSWORD='${PG_SUPERPASS}' psql -v ON_ERROR_STOP=1 -h haproxy -p 5432 -U '${PG_SUPERUSER}' -d postgres -Atqc \"DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${PG_APP_USER}') THEN CREATE ROLE ${PG_APP_USER} LOGIN PASSWORD '${PG_APP_PASS}'; END IF; END \\\$\\\$;\""

if ! compose_base exec -T psql-client bash -lc \
  "PGPASSWORD='${PG_SUPERPASS}' psql -h haproxy -p 5432 -U '${PG_SUPERUSER}' -d postgres -Atqc \"SELECT 1 FROM pg_database WHERE datname='${PG_APP_DB}';\"" | grep -q 1; then
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' psql -v ON_ERROR_STOP=1 -h haproxy -p 5432 -U '${PG_SUPERUSER}' -d postgres -Atqc \"CREATE DATABASE ${PG_APP_DB} OWNER ${PG_APP_USER};\""
fi

compose_base exec -T psql-client bash -lc \
  "PGPASSWORD='${PG_SUPERPASS}' psql -v ON_ERROR_STOP=1 -h haproxy -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"CREATE TABLE IF NOT EXISTS healthcheck(id serial primary key, created_at timestamptz default now());\""

echo "Inicializacao concluida"
