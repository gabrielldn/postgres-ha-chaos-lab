#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/run_id.sh"
source "$(dirname "$0")/lib/cluster.sh"

EVID_DIR="${ARTIFACT_DIR}"
CHAOS_DIR="${EVID_DIR}/chaos"
DB_DIR="${EVID_DIR}/db"
METRICS_DIR="${EVID_DIR}/metrics"
HAPROXY_DIR="${EVID_DIR}/haproxy"
ETCD_DIR="${EVID_DIR}/etcd"
VERSIONS_DIR="${EVID_DIR}/versions"

mkdir -p "${CHAOS_DIR}" "${DB_DIR}" "${METRICS_DIR}" "${HAPROXY_DIR}" "${ETCD_DIR}" "${VERSIONS_DIR}"

verify_failed=false

run_capture() {
  local outfile="$1"
  shift
  if "$@" > "${outfile}" 2>&1; then
    return 0
  fi
  verify_failed=true
  return 1
}

# Snapshot de versoes reais (reprodutibilidade)
run_capture "${VERSIONS_DIR}/postgres-version.txt" compose_base exec -T pg1 postgres --version || true
run_capture "${VERSIONS_DIR}/patroni-version.txt" compose_base exec -T pg1 patroni --version || true
run_capture "${VERSIONS_DIR}/pgbackrest-version.txt" compose_base exec -T pg1 pgbackrest version || true
run_capture "${VERSIONS_DIR}/etcd-version.txt" compose_base exec -T etcd1 etcd --version || true
run_capture "${VERSIONS_DIR}/haproxy-version.txt" compose_base exec -T haproxy haproxy -v || true

docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Digest}}' \
  | grep -E 'etcd|haproxy|minio|toxiproxy|pumba|prometheus|grafana|postgres-exporter|node-exporter|postgres-ha-chaos-lab-pg|python' \
  > "${VERSIONS_DIR}/docker-images.txt" || true

# Estado do cluster
patronictl_list_json > "${DB_DIR}/patronictl-list.json" 2>"${DB_DIR}/patronictl-list.err" || verify_failed=true
leader_now="$(jq -r '.[] | select(.Role == "Leader") | .Member' "${DB_DIR}/patronictl-list.json" 2>/dev/null | head -n1 || true)"

for port in 18081 18082 18083; do
  curl -fsS "http://127.0.0.1:${port}/primary" > "${DB_DIR}/rest-${port}-primary.txt" 2>&1 || true
  curl -fsS "http://127.0.0.1:${port}/replica" > "${DB_DIR}/rest-${port}-replica.txt" 2>&1 || true
  curl -fsS "http://127.0.0.1:${port}/replica?lag=${REPLICA_LAG_MAX_BYTES}" > "${DB_DIR}/rest-${port}-replica-lag.txt" 2>&1 || true
done

for node in pg1 pg2 pg3; do
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' psql -h '${node}' -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"SELECT pg_is_in_recovery();\"" \
    > "${DB_DIR}/${node}-is-in-recovery.txt" 2>&1 || verify_failed=true
done

for node in pg1 pg2 pg3; do
  is_recovery="$(tr -d '[:space:]' < "${DB_DIR}/${node}-is-in-recovery.txt" 2>/dev/null || echo unknown)"
  if [[ "${is_recovery}" == "t" ]]; then
    compose_base exec -T psql-client bash -lc \
      "PGPASSWORD='${PG_SUPERPASS}' psql -h '${node}' -p 5432 -U '${PG_SUPERUSER}' -d '${PG_APP_DB}' -Atqc \"SELECT now(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();\"" \
      > "${DB_DIR}/${node}-lsn.txt" 2>&1 || true
  fi
done

# Backups / archive
primary="$(wait_for_primary 30 || true)"
if [[ -n "${primary}" && "${primary}" != "null" ]]; then
  compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" info > "${DB_DIR}/pgbackrest-info.txt" 2>&1 || verify_failed=true
  compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" check > "${DB_DIR}/pgbackrest-check.txt" 2>&1 || verify_failed=true
else
  echo "Sem primario disponivel para pgbackrest check" > "${DB_DIR}/pgbackrest-check.txt"
  verify_failed=true
fi

# HAProxy e metricas
curl -fsS "http://127.0.0.1:${HAPROXY_STATS_PORT}/stats;csv" > "${HAPROXY_DIR}/stats.csv" 2>&1 || verify_failed=true
curl -fsS "http://127.0.0.1:${HAPROXY_STATS_PORT}/stats" > "${HAPROXY_DIR}/stats.html" 2>&1 || true
curl -fsS "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/alerts" > "${METRICS_DIR}/prometheus-alerts.json" 2>&1 || true
curl -fsS "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query?query=up" > "${METRICS_DIR}/prometheus-up.json" 2>&1 || true

# etcd quorum evidencias
compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint status --cluster -w table' > "${ETCD_DIR}/endpoint-status.txt" 2>&1 || true
compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint health --cluster -w table' > "${ETCD_DIR}/endpoint-health.txt" 2>&1 || true

# Resultados consolidados de caos/PITR (quando executados no mesmo RUN_ID)
rto_ms="n/a"
rto_slo_pass="n/a"
leader_before="n/a"
leader_after="n/a"
if [[ -f "${CHAOS_DIR}/primary-kill/result.json" ]]; then
  rto_ms="$(jq -r '.rto_ms' "${CHAOS_DIR}/primary-kill/result.json")"
  rto_slo_pass="$(jq -r '.rto_slo_pass' "${CHAOS_DIR}/primary-kill/result.json")"
  leader_before="$(jq -r '.leader_before' "${CHAOS_DIR}/primary-kill/result.json")"
  leader_after="$(jq -r '.leader_after' "${CHAOS_DIR}/primary-kill/result.json")"
fi

pitr_pass="n/a"
if [[ -f "${EVID_DIR}/pitr/result.json" ]]; then
  pitr_pass="$(jq -r '.pitr_pass' "${EVID_DIR}/pitr/result.json")"
fi

etcd_quorum_pass="n/a"
if [[ -f "${CHAOS_DIR}/etcd-quorum/result.json" ]]; then
  etcd_quorum_pass="$(jq -r '(.new_leader_detected_during_quorum_loss == false) and (.split_brain_detected == false)' "${CHAOS_DIR}/etcd-quorum/result.json" 2>/dev/null || echo "n/a")"
fi

replica_lag_pass="n/a"
if [[ -f "${CHAOS_DIR}/replica-lag/result.json" ]]; then
  replica_lag_pass="$(jq -r '(.client_proof_pass == true) and (.haproxy_removed == true)' "${CHAOS_DIR}/replica-lag/result.json" 2>/dev/null || echo "n/a")"
fi

primary_etcd_partition_pass="n/a"
if [[ -f "${CHAOS_DIR}/primary-etcd-partition/result.json" ]]; then
  primary_etcd_partition_pass="$(jq -r '.scenario_pass == true' "${CHAOS_DIR}/primary-etcd-partition/result.json" 2>/dev/null || echo "n/a")"
fi

alerts_firing_count="n/a"
alerts_firing_names="n/a"
if [[ -f "${METRICS_DIR}/prometheus-alerts.json" ]]; then
  alerts_firing_count="$(jq -r '.data.alerts | map(select(.state == "firing")) | length' "${METRICS_DIR}/prometheus-alerts.json" 2>/dev/null || echo "n/a")"
  alerts_firing_names="$(jq -r '.data.alerts | map(select(.state == "firing") | .labels.alertname) | unique | join(", ")' "${METRICS_DIR}/prometheus-alerts.json" 2>/dev/null || echo "n/a")"
  if [[ -z "${alerts_firing_names}" ]]; then
    alerts_firing_names="none"
  fi
fi

cat > "${EVID_DIR}/SUMMARY.md" <<EOF_SUMMARY
# Evidence Summary (${RUN_ID})

## Cluster
- Leader atual: ${leader_now:-unknown}
- Leader before failover: ${leader_before}
- Leader after failover: ${leader_after}

## RTO
- FAILOVER_SLO_MS: ${FAILOVER_SLO_MS}
- rto_ms: ${rto_ms}
- rto_slo_pass: ${rto_slo_pass}

## PITR
- pitr_pass: ${pitr_pass}
- Regra validada: marker_before existe, marker_after ausente

## Chaos
- etcd_quorum_safety_pass: ${etcd_quorum_pass}
- primary_etcd_partition_pass: ${primary_etcd_partition_pass}
- replica_lag_ro_proof_pass: ${replica_lag_pass}

## Alertas
- firing_alerts_count: ${alerts_firing_count}
- firing_alerts: ${alerts_firing_names}

## Arquivos-chave
- Patroni list: db/patronictl-list.json
- REST checks: db/rest-*.txt
- pgBackRest: db/pgbackrest-info.txt, db/pgbackrest-check.txt
- HAProxy stats: haproxy/stats.csv
- etcd health/status: etcd/endpoint-health.txt, etcd/endpoint-status.txt
- Versoes reais: versions/*.txt

## Runbooks
- Failover: runbooks/failover-primario.md
- Quorum etcd: runbooks/perda-quorum-etcd.md
- Particao primario-etcd: runbooks/particao-primario-etcd.md
- Archive break: runbooks/quebra-archive.md
- PITR: runbooks/pitr-restore.md
EOF_SUMMARY

python3 - <<PY
import pathlib
import zipfile

root = pathlib.Path(${EVID_DIR@Q})
zip_path = root.with_suffix('.zip')
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            zf.write(path, path.relative_to(root.parent))
print(zip_path)
PY

if [[ "${verify_failed}" == "true" ]]; then
  echo "verify detectou falhas. Consulte ${EVID_DIR}/SUMMARY.md e artefatos." >&2
  exit 1
fi

echo "Evidence pack gerado em ${EVID_DIR}"
