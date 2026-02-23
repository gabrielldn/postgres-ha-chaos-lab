#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/chaos/etcd-quorum"
mkdir -p "${ART_DIR}"

node_port() {
  case "$1" in
    pg1) echo 18081 ;;
    pg2) echo 18082 ;;
    pg3) echo 18083 ;;
    *) return 1 ;;
  esac
}

leader_before="$(get_primary)"
if [[ -z "${leader_before}" || "${leader_before}" == "null" ]]; then
  echo "Nao foi possivel identificar o lider antes do teste de quorum" >&2
  exit 1
fi

patronictl_list_json > "${ART_DIR}/patronictl-before.json" || true

compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint status --cluster -w table' > "${ART_DIR}/etcd-status-before.txt" 2>&1 || true
compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint health --cluster -w table' > "${ART_DIR}/etcd-health-before.txt" 2>&1 || true

compose_base stop etcd2 etcd3 >/dev/null
sleep 5

compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint status --cluster -w table' > "${ART_DIR}/etcd-status-no-quorum.txt" 2>&1 || true
compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint health --cluster -w table' > "${ART_DIR}/etcd-health-no-quorum.txt" 2>&1 || true

compose_base stop "${leader_before}" >/dev/null

new_leader_detected=false
split_brain=false
for _ in $(seq 1 30); do
  primary_count=0
  for node in pg1 pg2 pg3; do
    port="$(node_port "${node}" || true)"
    if [[ -z "${port}" ]]; then
      continue
    fi
    if curl -fsS "http://127.0.0.1:${port}/primary" >/dev/null 2>&1; then
      primary_count=$((primary_count + 1))
      if [[ "${node}" != "${leader_before}" ]]; then
        new_leader_detected=true
      fi
    fi
  done
  printf '%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${primary_count}" >> "${ART_DIR}/primary-count.csv"
  if (( primary_count > 1 )); then
    split_brain=true
  fi
  sleep 2
done

compose_base up -d etcd2 etcd3 "${leader_before}" >/dev/null
sleep 8

compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint status --cluster -w table' > "${ART_DIR}/etcd-status-after.txt" 2>&1 || true
compose_base exec -T etcd1 sh -ec 'ETCDCTL_API=3 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint health --cluster -w table' > "${ART_DIR}/etcd-health-after.txt" 2>&1 || true

leader_after="$(wait_for_primary 120 || true)"
patronictl_list_json > "${ART_DIR}/patronictl-after.json" || true

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "leader_before": "${leader_before}",
  "leader_after": "${leader_after:-unknown}",
  "new_leader_detected_during_quorum_loss": ${new_leader_detected},
  "split_brain_detected": ${split_brain}
}
JSON

if [[ "${new_leader_detected}" == "true" || "${split_brain}" == "true" ]]; then
  echo "Falha de safety: houve promocao inesperada ou split brain durante perda de quorum" >&2
  exit 1
fi

echo "Safety validada: sem promocao com quorum perdido"
