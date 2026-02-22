#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  ENV_FILE="${ROOT_DIR}/.env.example"
fi

# shellcheck disable=SC1090
existing_run_id="${RUN_ID:-}"
set -a
source "${ENV_FILE}"
# shellcheck disable=SC1091
source "${ROOT_DIR}/compose/images.lock.env"
set +a

if [[ -n "${existing_run_id}" ]]; then
  RUN_ID="${existing_run_id}"
  export RUN_ID
fi

compose_base() {
  docker compose \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_DIR}/compose/images.lock.env" \
    -f "${ROOT_DIR}/compose/docker-compose.yml" \
    "$@"
}

compose_pumba() {
  docker compose \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_DIR}/compose/images.lock.env" \
    -f "${ROOT_DIR}/compose/docker-compose.yml" \
    -f "${ROOT_DIR}/compose/docker-compose.pumba.yml" \
    --profile pumba \
    "$@"
}

compose_keepalived() {
  docker compose \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_DIR}/compose/images.lock.env" \
    -f "${ROOT_DIR}/compose/docker-compose.yml" \
    -f "${ROOT_DIR}/compose/docker-compose.keepalived.yml" \
    --profile keepalived \
    "$@"
}

compose_restore() {
  docker compose \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_DIR}/compose/images.lock.env" \
    -f "${ROOT_DIR}/compose/docker-compose.yml" \
    --profile restore \
    "$@"
}

patronictl_list_json() {
  if compose_base ps --status running --services | grep -qx "pg1"; then
    compose_base exec -T pg1 patronictl -c /etc/patroni/patroni.yml list -f json
    return
  fi

  echo "WARN: pg1 indisponivel; fallback temporario para pg2." >&2
  compose_base exec -T pg2 patronictl -c /etc/patroni/patroni.yml list -f json
}

get_primary() {
  patronictl_list_json | jq -r '.[] | select(.Role == "Leader") | .Member' | head -n1
}

get_replicas() {
  patronictl_list_json | jq -r '.[] | select(.Role == "Replica") | .Member'
}

wait_for_primary() {
  local timeout_s="${1:-60}"
  local deadline=$((SECONDS + timeout_s))
  local leader=""

  while (( SECONDS < deadline )); do
    leader="$(get_primary || true)"
    if [[ -n "${leader}" && "${leader}" != "null" ]]; then
      printf '%s\n' "${leader}"
      return 0
    fi
    sleep 1
  done

  return 1
}

sql_via_haproxy_rw() {
  local sql="$1"
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' timeout 10 psql -v ON_ERROR_STOP=1 \"host=haproxy port=5432 user=${PG_SUPERUSER} dbname=${PG_APP_DB} connect_timeout=2 sslmode=disable\" -c \"SET statement_timeout='5s'; ${sql}\" -Atq"
}

sql_via_haproxy_ro() {
  local sql="$1"
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' timeout 10 psql -v ON_ERROR_STOP=1 \"host=haproxy port=5433 user=${PG_SUPERUSER} dbname=${PG_APP_DB} connect_timeout=2 sslmode=disable\" -c \"SET statement_timeout='5s'; ${sql}\" -Atq"
}

sql_direct_node() {
  local node="$1"
  local sql="$2"
  compose_base exec -T psql-client bash -lc \
    "PGPASSWORD='${PG_SUPERPASS}' timeout 10 psql -v ON_ERROR_STOP=1 \"host=${node} port=5432 user=${PG_SUPERUSER} dbname=${PG_APP_DB} connect_timeout=2 sslmode=disable\" -c \"SET statement_timeout='5s'; ${sql}\" -Atq"
}

ensure_artifact_dir() {
  local dir="$1"
  mkdir -p "${dir}"
}
