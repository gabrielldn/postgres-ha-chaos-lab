#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/chaos/replica-lag"
mkdir -p "${ART_DIR}"

node_rest_port() {
  case "$1" in
    pg1) echo 18081 ;;
    pg2) echo 18082 ;;
    pg3) echo 18083 ;;
    *) return 1 ;;
  esac
}

target_replica="$(get_replicas | head -n1)"
if [[ -z "${target_replica}" ]]; then
  echo "Nenhuma replica encontrada para o teste de lag" >&2
  exit 1
fi
target_rest_port="$(node_rest_port "${target_replica}")"

target_addr="$(sql_direct_node "${target_replica}" "SELECT inet_server_addr()::text;" | head -n1 | tr -d '[:space:]')"
leader="$(get_primary)"
if [[ -z "${leader}" || "${leader}" == "null" ]]; then
  echo "Nao foi possivel identificar o lider para o cenario de lag" >&2
  exit 1
fi
leader_ip="$(compose_base exec -T "${target_replica}" bash -lc "getent hosts ${leader} | awk '{print \$1}' | head -n1" | tr -d '[:space:]')"
if [[ -z "${leader_ip}" ]]; then
  echo "Nao foi possivel resolver IP do lider (${leader}) dentro da replica alvo" >&2
  exit 1
fi

{
  echo "target_replica=${target_replica}"
  echo "target_addr=${target_addr}"
  echo "target_rest_port=${target_rest_port}"
  echo "leader=${leader}"
  echo "leader_ip=${leader_ip}"
} > "${ART_DIR}/context.txt"

cleanup() {
  compose_base exec -u root -T "${target_replica}" bash -lc "iptables -D INPUT -s ${leader_ip} -p tcp --sport 5432 -j DROP" >/dev/null 2>&1 || true
  compose_base exec -u root -T "${target_replica}" bash -lc "iptables -D OUTPUT -d ${leader_ip} -p tcp --dport 5432 -j DROP" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Isola somente o fluxo de replicacao entre lider -> replica alvo.
compose_base exec -u root -T "${target_replica}" bash -lc "iptables -I INPUT -s ${leader_ip} -p tcp --sport 5432 -j DROP"
compose_base exec -u root -T "${target_replica}" bash -lc "iptables -I OUTPUT -d ${leader_ip} -p tcp --dport 5432 -j DROP"
compose_base exec -u root -T "${target_replica}" bash -lc "iptables -S INPUT | grep -- \"-s ${leader_ip} -p tcp -m tcp --sport 5432 -j DROP\"" > "${ART_DIR}/iptables-rules.txt" || true
compose_base exec -u root -T "${target_replica}" bash -lc "iptables -S OUTPUT | grep -- \"-d ${leader_ip} -p tcp -m tcp --dport 5432 -j DROP\"" >> "${ART_DIR}/iptables-rules.txt" || true

leader_lsn_before="$(sql_direct_node "${leader}" "SELECT pg_current_wal_lsn();" | tr -d '[:space:]' || true)"
target_replay_before="$(sql_direct_node "${target_replica}" "SELECT pg_last_wal_replay_lsn();" | tr -d '[:space:]' || true)"
if [[ -n "${leader_lsn_before}" && -n "${target_replay_before}" ]]; then
  sql_direct_node "${leader}" "SELECT pg_wal_lsn_diff('${leader_lsn_before}', '${target_replay_before}');" > "${ART_DIR}/lag-before-bytes.txt" || true
fi
sleep 2

sql_via_haproxy_rw "CREATE TABLE IF NOT EXISTS chaos_load_big (id bigserial primary key, run_id text not null, payload text not null, created_at timestamptz not null default now());" >/dev/null
(
  # Gera volume de WAL suficiente para ultrapassar o lag maximo (default 10MB).
  for _ in $(seq 1 6); do
    sql_via_haproxy_rw "INSERT INTO chaos_load_big(run_id, payload) SELECT '${RUN_ID}', repeat(md5(random()::text || clock_timestamp()::text), 16384) FROM generate_series(1,20);" >/dev/null 2>&1 || true
    sleep 1
  done
) &
writer_pid=$!

for _ in $(seq 1 30); do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "${target_rest_port}" ]]; then
    if code="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${target_rest_port}/replica?lag=${REPLICA_LAG_MAX_BYTES}")"; then
      echo "${ts},${code}" >> "${ART_DIR}/target-replica-lag-endpoint.csv"
    fi
  fi
  if out="$(sql_via_haproxy_ro "SELECT inet_server_addr()::text || ',' || inet_server_port()::text;" 2>/dev/null)"; then
    echo "${ts},${out}" >> "${ART_DIR}/ro-client.csv"
  else
    echo "${ts},ERROR" >> "${ART_DIR}/ro-client.csv"
  fi
  sleep 2
done

wait "${writer_pid}" || true
leader_lsn_after="$(sql_direct_node "${leader}" "SELECT pg_current_wal_lsn();" | tr -d '[:space:]' || true)"
target_replay_after="$(sql_direct_node "${target_replica}" "SELECT pg_last_wal_replay_lsn();" | tr -d '[:space:]' || true)"
if [[ -n "${leader_lsn_after}" && -n "${target_replay_after}" ]]; then
  sql_direct_node "${leader}" "SELECT pg_wal_lsn_diff('${leader_lsn_after}', '${target_replay_after}');" > "${ART_DIR}/lag-after-bytes.txt" || true
fi

curl -fsS "http://127.0.0.1:${HAPROXY_STATS_PORT}/stats;csv" > "${ART_DIR}/haproxy-stats.csv" 2>/dev/null || true

client_proof_pass=true
effective_client_samples="${ART_DIR}/ro-client-effective.csv"
degraded_since="$(awk -F',' '$2 != "200" {print $1; exit}' "${ART_DIR}/target-replica-lag-endpoint.csv" 2>/dev/null || true)"
if [[ -n "${degraded_since}" ]]; then
  awk -F',' -v ts="${degraded_since}" '$1 >= ts {print $0}' "${ART_DIR}/ro-client.csv" > "${effective_client_samples}" || true
else
  : > "${effective_client_samples}"
  client_proof_pass=false
fi
if [[ -n "${target_addr}" ]] && grep -Fq "${target_addr}" "${effective_client_samples}"; then
  client_proof_pass=false
fi

haproxy_line="$(grep "^patroni_replicas,${target_replica}," "${ART_DIR}/haproxy-stats.csv" || true)"
haproxy_removed=false
if [[ "${haproxy_line}" == *",DOWN,"* || "${haproxy_line}" == *",MAINT,"* || "${haproxy_line}" == *",NOLB,"* ]]; then
  haproxy_removed=true
fi

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "target_replica": "${target_replica}",
  "target_addr": "${target_addr}",
  "degraded_since": "${degraded_since:-}",
  "client_proof_pass": ${client_proof_pass},
  "haproxy_removed": ${haproxy_removed}
}
JSON

if [[ "${client_proof_pass}" != "true" || "${haproxy_removed}" != "true" ]]; then
  echo "Falha: exclusao da replica degradada nao comprovada por cliente e/ou HAProxy (${target_replica}/${target_addr})" >&2
  exit 1
fi

echo "Replica degradada removida do fluxo RO segundo prova cliente-side"
