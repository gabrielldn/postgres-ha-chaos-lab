#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/run_id.sh"
source "$(dirname "$0")/../../scripts/lib/cluster.sh"

ART_DIR="${ARTIFACT_DIR}/chaos/archive-break"
mkdir -p "${ART_DIR}"

primary="$(wait_for_primary 120)"
if [[ -z "${primary}" ]]; then
  echo "Nenhum primario disponivel" >&2
  exit 1
fi

compose_base stop minio >/dev/null
sleep 3

check_failed=false
if compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" check > "${ART_DIR}/pgbackrest-check.txt" 2>&1; then
  check_failed=false
else
  check_failed=true
fi

compose_base up -d minio >/dev/null
compose_base up -d minio-init >/dev/null

cat > "${ART_DIR}/result.json" <<JSON
{
  "run_id": "${RUN_ID}",
  "check_failed_as_expected": ${check_failed}
}
JSON

if [[ "${check_failed}" != "true" ]]; then
  echo "Falha: pgbackrest check nao falhou mesmo com MinIO indisponivel" >&2
  exit 1
fi

echo "Falha de archive detectada conforme esperado"
