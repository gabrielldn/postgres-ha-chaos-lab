#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/pitr"
mkdir -p "${ART_DIR}"

before_marker="before_${RUN_ID}"
after_marker="after_${RUN_ID}"
restore_point="rp_${RUN_ID}"

primary="$(wait_for_primary 120)"
if [[ -z "${primary}" ]]; then
  echo "Nenhum primario disponivel para PITR" >&2
  exit 1
fi

sql_via_haproxy_rw "CREATE TABLE IF NOT EXISTS pitr_markers (id bigserial primary key, marker text not null unique, phase text not null, created_at timestamptz not null default now());"
sql_via_haproxy_rw "INSERT INTO pitr_markers(marker, phase) VALUES ('${before_marker}', 'before') ON CONFLICT (marker) DO NOTHING;"
compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" --type=full backup | tee "${ART_DIR}/backup.log"
sql_via_haproxy_rw "SELECT pg_create_restore_point('${restore_point}');" | tee "${ART_DIR}/restore_point_lsn.txt"
sql_via_haproxy_rw "INSERT INTO pitr_markers(marker, phase) VALUES ('${after_marker}', 'after') ON CONFLICT (marker) DO NOTHING;"
sql_via_haproxy_rw "SELECT pg_switch_wal();" >/dev/null || true
sleep 2

sql_direct_node "${primary}" "SELECT timeline_id FROM pg_control_checkpoint();" > "${ART_DIR}/timeline_primary.txt" || true

compose_restore up -d restore

compose_restore exec -T restore bash -lc "rm -rf /var/lib/postgresql/data/*"
compose_restore exec -T restore bash -lc "mkdir -p /etc/pgbackrest"

compose_restore exec -T restore bash -lc "cat > /etc/pgbackrest/pgbackrest.conf <<CONF
[global]
repo1-type=s3
repo1-path=/pgbackrest
repo1-s3-uri-style=path
repo1-s3-endpoint=http://minio:9000
repo1-s3-bucket=${MINIO_BUCKET}
repo1-s3-region=us-east-1
repo1-s3-key=${MINIO_ROOT_USER}
repo1-s3-key-secret=${MINIO_ROOT_PASSWORD}
repo1-s3-verify-tls=n
start-fast=y
process-max=2
archive-async=n

[${BACKREST_STANZA}]
pg1-path=/var/lib/postgresql/data
pg1-port=5432
pg1-user=postgres
CONF"

compose_restore exec -T restore bash -lc "gosu postgres pgbackrest --stanza='${BACKREST_STANZA}' --type=name --target='${restore_point}' --target-action=promote --delta --pg1-path=/var/lib/postgresql/data restore" | tee "${ART_DIR}/restore.log"

compose_restore exec -T restore bash -lc "chown -R postgres:postgres /var/lib/postgresql/data"
compose_restore exec -T restore bash -lc "gosu postgres /usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data -o \"-p 5432 -c listen_addresses='*'\" -w start"

before_count="$(compose_restore exec -T restore bash -lc "PGPASSWORD='${PG_SUPERPASS}' psql -h 127.0.0.1 -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"SELECT count(*) FROM pitr_markers WHERE marker = '${before_marker}';\"" | tr -d '[:space:]')"
after_count="$(compose_restore exec -T restore bash -lc "PGPASSWORD='${PG_SUPERPASS}' psql -h 127.0.0.1 -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"SELECT count(*) FROM pitr_markers WHERE marker = '${after_marker}';\"" | tr -d '[:space:]')"

compose_restore exec -T restore bash -lc "PGPASSWORD='${PG_SUPERPASS}' psql -h 127.0.0.1 -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"SELECT timeline_id FROM pg_control_checkpoint();\"" > "${ART_DIR}/timeline_restore.txt" || true

compose_restore exec -T restore bash -lc "gosu postgres /usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data -m fast -w stop"

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "restore_point": "${restore_point}",
  "before_marker": "${before_marker}",
  "after_marker": "${after_marker}",
  "before_count": ${before_count:-0},
  "after_count": ${after_count:-0},
  "pitr_pass": $([[ "${before_count:-0}" -ge 1 && "${after_count:-0}" -eq 0 ]] && echo true || echo false)
}
JSON

if [[ "${before_count:-0}" -lt 1 || "${after_count:-0}" -ne 0 ]]; then
  echo "PITR falhou: before_count=${before_count:-0}, after_count=${after_count:-0}" >&2
  exit 1
fi

echo "PITR validado com sucesso (before presente, after ausente)."
