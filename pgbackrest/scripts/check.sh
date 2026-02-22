#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../scripts/lib/cluster.sh"

primary="$(wait_for_primary 120)"
if [[ -z "${primary}" ]]; then
  echo "Nenhum primario disponivel para check" >&2
  exit 1
fi

compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" info
compose_base exec -T "${primary}" gosu postgres pgbackrest --stanza="${BACKREST_STANZA}" check
