#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/compose/images.lock.env"
TMP_FILE="${LOCK_FILE}.tmp"

# shellcheck disable=SC1090
source "${LOCK_FILE}"

resolve_digest() {
  local ref="$1"
  if [[ "${ref}" == *@sha256:* ]]; then
    printf '%s\n' "${ref}"
    return 0
  fi

  local digest
  digest="$(docker buildx imagetools inspect "${ref}" --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"')"
  if [[ -z "${digest}" ]]; then
    return 1
  fi

  printf '%s@%s\n' "${ref}" "${digest}"
}

write_var() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "${name}" "${value}" >> "${TMP_FILE}"
}

: > "${TMP_FILE}"
printf '# Arquivo gerado por scripts/lock-images.sh\n' >> "${TMP_FILE}"
printf '# Atualizado em UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${TMP_FILE}"

external_vars=(
  IMG_ETCD
  IMG_HAPROXY
  IMG_MINIO
  IMG_MINIO_MC
  IMG_TOXIPROXY
  IMG_PUMBA
  IMG_PROMETHEUS
  IMG_GRAFANA
  IMG_POSTGRES_EXPORTER
  IMG_NODE_EXPORTER
  IMG_KEEPALIVED
  IMG_PSQL_CLIENT
  IMG_TEST_RUNNER
)

for var in "${external_vars[@]}"; do
  current="${!var}"
  if locked="$(resolve_digest "${current}")"; then
    write_var "${var}" "${locked}"
  else
    echo "WARN: nao foi possivel resolver digest para ${var} (${current}), mantendo referencia atual" >&2
    write_var "${var}" "${current}"
  fi
done

# Imagem local custom nao entra em digest lock externo.
write_var "IMG_PG_PATRONI" "${IMG_PG_PATRONI}"

mv "${TMP_FILE}" "${LOCK_FILE}"
echo "Arquivo atualizado: ${LOCK_FILE}"
