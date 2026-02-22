#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/chaos/primary-etcd-partition"
mkdir -p "${ART_DIR}"

leader="$(get_primary)"
if [[ -z "${leader}" || "${leader}" == "null" ]]; then
  echo "Nao foi possivel identificar o primario" >&2
  exit 1
fi

printf 'leader_before=%s\n' "${leader}" > "${ART_DIR}/context.txt"

compose_pumba run --rm pumba netem --duration 25s loss --percent 100 "re2:^${leader}$" > "${ART_DIR}/pumba.log" 2>&1 || true

for i in $(seq 1 15); do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if sql_via_haproxy_rw "SELECT 1;" >/dev/null 2>&1; then
    echo "${ts},rw_ok" >> "${ART_DIR}/rw-probe.csv"
  else
    echo "${ts},rw_fail" >> "${ART_DIR}/rw-probe.csv"
  fi
  sleep 2
done

for port in 18081 18082 18083; do
  curl -fsS "http://127.0.0.1:${port}/primary" > "${ART_DIR}/primary-${port}.txt" 2>&1 || true
  curl -fsS "http://127.0.0.1:${port}/replica" > "${ART_DIR}/replica-${port}.txt" 2>&1 || true
done

leader_after="$(wait_for_primary 120 || true)"
printf 'leader_after=%s\n' "${leader_after:-unknown}" >> "${ART_DIR}/context.txt"

echo "Cenario de particao concluido"
