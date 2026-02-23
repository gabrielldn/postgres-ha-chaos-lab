#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/chaos/primary-etcd-partition"
mkdir -p "${ART_DIR}"

node_port() {
  case "$1" in
    pg1) echo 18081 ;;
    pg2) echo 18082 ;;
    pg3) echo 18083 ;;
    *) return 1 ;;
  esac
}

discover_etcd_ip() {
  local etcd_node="$1"
  compose_base exec -T "${leader}" bash -lc "getent ahostsv4 ${etcd_node} | awk 'NR==1 {print \$1}'" | tr -d '[:space:]'
}

drop_etcd_rules() {
  local etcd_ip
  for etcd_ip in "${etcd_ips[@]}"; do
    compose_base exec -u root -T "${leader}" bash -lc "iptables -D OUTPUT -d ${etcd_ip} -p tcp --dport 2379 -j DROP" >/dev/null 2>&1 || true
    compose_base exec -u root -T "${leader}" bash -lc "iptables -D INPUT -s ${etcd_ip} -p tcp --sport 2379 -j DROP" >/dev/null 2>&1 || true
  done
}

record_probe() {
  local phase="$1"
  local ts rw_state primary_count node port

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if sql_via_haproxy_rw "SELECT 1;" >/dev/null 2>&1; then
    rw_state="rw_ok"
    if [[ "${phase}" == "recovery" ]]; then
      rw_ok_after_heal=true
    fi
  else
    rw_state="rw_fail"
    if [[ "${phase}" == "partition" ]]; then
      rw_fail_during_partition=true
    fi
  fi

  primary_count=0
  for node in pg1 pg2 pg3; do
    port="$(node_port "${node}" || true)"
    if [[ -z "${port}" ]]; then
      continue
    fi
    if curl -fsS "http://127.0.0.1:${port}/primary" >/dev/null 2>&1; then
      primary_count=$((primary_count + 1))
      if [[ "${node}" != "${leader}" ]]; then
        new_leader_detected=true
      fi
    fi
  done

  if (( primary_count > 1 )); then
    split_brain_detected=true
  fi

  printf '%s,%s,%s,%s\n' "${ts}" "${phase}" "${rw_state}" "${primary_count}" >> "${ART_DIR}/timeline.csv"
}

leader="$(get_primary)"
if [[ -z "${leader}" || "${leader}" == "null" ]]; then
  echo "Nao foi possivel identificar o primario" >&2
  exit 1
fi

printf 'leader_before=%s\n' "${leader}" > "${ART_DIR}/context.txt"

etcd_ips=()
for etcd_node in etcd1 etcd2 etcd3; do
  etcd_ip="$(discover_etcd_ip "${etcd_node}" || true)"
  if [[ -n "${etcd_ip}" ]]; then
    etcd_ips+=("${etcd_ip}")
  fi
done

if (( ${#etcd_ips[@]} < 2 )); then
  echo "Nao foi possivel resolver IPs do quorum etcd a partir do leader ${leader}" >&2
  exit 1
fi

{
  echo "partition_method=iptables"
  printf 'etcd_ips=%s\n' "${etcd_ips[*]}"
} >> "${ART_DIR}/context.txt"

rules_applied=true
for etcd_ip in "${etcd_ips[@]}"; do
  if ! compose_base exec -u root -T "${leader}" bash -lc "iptables -I OUTPUT -d ${etcd_ip} -p tcp --dport 2379 -j DROP"; then
    rules_applied=false
  fi
  if ! compose_base exec -u root -T "${leader}" bash -lc "iptables -I INPUT -s ${etcd_ip} -p tcp --sport 2379 -j DROP"; then
    rules_applied=false
  fi
done

compose_base exec -u root -T "${leader}" bash -lc "iptables -S OUTPUT | grep -- '--dport 2379 -j DROP'" > "${ART_DIR}/iptables-rules.txt" 2>&1 || true
compose_base exec -u root -T "${leader}" bash -lc "iptables -S INPUT | grep -- '--sport 2379 -j DROP'" >> "${ART_DIR}/iptables-rules.txt" 2>&1 || true

trap drop_etcd_rules EXIT

rw_fail_during_partition=false
rw_ok_after_heal=false
split_brain_detected=false
new_leader_detected=false

for _ in $(seq 1 14); do
  record_probe "partition"
  sleep 2
done

drop_etcd_rules
trap - EXIT

for _ in $(seq 1 14); do
  record_probe "recovery"
  sleep 2
done

awk -F',' '$2 == "partition" {print $1 "," $3}' "${ART_DIR}/timeline.csv" > "${ART_DIR}/rw-probe.csv"
awk -F',' '{print $1 "," $4}' "${ART_DIR}/timeline.csv" > "${ART_DIR}/primary-count.csv"

for port in 18081 18082 18083; do
  curl -fsS "http://127.0.0.1:${port}/primary" > "${ART_DIR}/primary-${port}.txt" 2>&1 || true
  curl -fsS "http://127.0.0.1:${port}/replica" > "${ART_DIR}/replica-${port}.txt" 2>&1 || true
done

leader_after="$(wait_for_primary 120 || true)"
printf 'leader_after=%s\n' "${leader_after:-unknown}" >> "${ART_DIR}/context.txt"

patronictl_list_json > "${ART_DIR}/patronictl-after.json" 2>"${ART_DIR}/patronictl-after.err" || true
leader_count_after="$(jq '[.[] | select(.Role == "Leader")] | length' "${ART_DIR}/patronictl-after.json" 2>/dev/null || echo 0)"

partition_effect_observed=false
if [[ "${rw_fail_during_partition}" == "true" ]]; then
  partition_effect_observed=true
fi

rw_recovered=false
if [[ "${rw_ok_after_heal}" == "true" ]]; then
  rw_recovered=true
fi

leader_after_valid=false
if [[ -n "${leader_after:-}" && "${leader_after}" != "null" && "${leader_after}" != "unknown" ]]; then
  leader_after_valid=true
fi

leader_changed=false
if [[ -n "${leader_after:-}" && "${leader_after}" != "${leader}" ]]; then
  leader_changed=true
fi

scenario_pass=false
if [[ "${rules_applied}" == "true" ]] \
  && [[ "${partition_effect_observed}" == "true" ]] \
  && [[ "${rw_recovered}" == "true" ]] \
  && [[ "${split_brain_detected}" != "true" ]] \
  && [[ "${leader_after_valid}" == "true" ]] \
  && (( leader_count_after <= 1 )); then
  scenario_pass=true
fi

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "leader_before": "${leader}",
  "leader_after": "${leader_after:-unknown}",
  "leader_changed": ${leader_changed},
  "partition_method": "iptables",
  "rules_applied": ${rules_applied},
  "partition_effect_observed": ${partition_effect_observed},
  "rw_recovered": ${rw_recovered},
  "new_leader_detected": ${new_leader_detected},
  "split_brain_detected": ${split_brain_detected},
  "leader_count_after": ${leader_count_after},
  "scenario_pass": ${scenario_pass}
}
JSON

if [[ "${scenario_pass}" != "true" ]]; then
  echo "Falha: cenario de particao sem criterios de aceite atendidos (rules_applied=${rules_applied}, partition_effect_observed=${partition_effect_observed}, rw_recovered=${rw_recovered}, split_brain_detected=${split_brain_detected}, leader_count_after=${leader_count_after})" >&2
  exit 1
fi

echo "Cenario de particao validado: safety sem split brain e recuperacao de RW comprovada"
