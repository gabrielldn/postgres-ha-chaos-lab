#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RUN_ID:-}" ]]; then
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
fi
export RUN_ID

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-${ROOT_DIR}/artifacts}"
ARTIFACT_DIR="${ARTIFACT_ROOT}/${RUN_ID}"
export ROOT_DIR ARTIFACT_ROOT ARTIFACT_DIR

mkdir -p "${ARTIFACT_DIR}"
