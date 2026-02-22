#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

SLO_MS="${FAILOVER_SLO_MS:-15000}"
ART_DIR="${ARTIFACT_DIR}/chaos/primary-kill"
mkdir -p "${ART_DIR}"

probe_rw_insert_fast() {
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' timeout 2 psql -v ON_ERROR_STOP=1 \"host=haproxy port=5432 user=${PG_SUPERUSER} dbname=${PG_APP_DB} connect_timeout=1 sslmode=disable\" -Atqc \"SET statement_timeout='1000ms'; INSERT INTO chaos_rto(run_id) VALUES ('${RUN_ID}');\""
}

patronictl_list_json > "${ART_DIR}/patronictl-before.json" || true
leader_before="$(get_primary)"
if [[ -z "${leader_before}" || "${leader_before}" == "null" ]]; then
  echo "Nao foi possivel identificar o lider atual" >&2
  exit 1
fi

ready=false
for _ in $(seq 1 60); do
  if sql_via_haproxy_rw "CREATE TABLE IF NOT EXISTS chaos_rto (id bigserial primary key, run_id text not null, created_at timestamptz not null default now());" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "${ready}" != "true" ]]; then
  echo "Falha: endpoint RW indisponivel antes do teste" >&2
  exit 1
fi

t0_ms="$(date +%s%3N)"
compose_base kill -s SIGKILL "${leader_before}" >/dev/null

write_ok=false
t1_ms=""
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if probe_rw_insert_fast >/dev/null 2>&1; then
    t1_ms="$(date +%s%3N)"
    write_ok=true
    break
  fi
  sleep 1
done

docker start "${leader_before}" >/dev/null 2>&1 || true

if [[ "${write_ok}" != "true" ]]; then
  echo "Falha: escrita RW nao voltou dentro do timeout" >&2
  t1_ms="$(date +%s%3N)"
fi

leader_after="$(wait_for_primary 120 || true)"
patronictl_list_json > "${ART_DIR}/patronictl-after.json" || true
leader_count="$(jq '[.[] | select(.Role == "Leader")] | length' "${ART_DIR}/patronictl-after.json" 2>/dev/null || echo 0)"

rto_ms=$((t1_ms - t0_ms))
rto_slo_pass=false
if (( rto_ms <= SLO_MS )) && [[ "${write_ok}" == "true" ]] && (( leader_count <= 1 )); then
  rto_slo_pass=true
fi

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "leader_before": "${leader_before}",
  "leader_after": "${leader_after:-unknown}",
  "t0_ms": ${t0_ms},
  "t1_ms": ${t1_ms},
  "rto_ms": ${rto_ms},
  "failover_slo_ms": ${SLO_MS},
  "rto_slo_pass": ${rto_slo_pass},
  "write_recovered": ${write_ok},
  "leader_count_after": ${leader_count}
}
JSON

if [[ "${rto_slo_pass}" != "true" ]]; then
  echo "SLO de failover violado: rto_ms=${rto_ms} (SLO=${SLO_MS})" >&2
  exit 1
fi

echo "Failover validado com rto_ms=${rto_ms} (SLO=${SLO_MS})"
