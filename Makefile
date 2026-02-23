SHELL := /bin/bash

ENV_FILE := .env
ENV_EXAMPLE := .env.example
COMPOSE_ENV := $(if $(wildcard $(ENV_FILE)),$(ENV_FILE),$(ENV_EXAMPLE))

COMPOSE_BASE = docker compose --env-file $(COMPOSE_ENV) --env-file compose/images.lock.env -f compose/docker-compose.yml
COMPOSE_PUMBA = docker compose --env-file $(COMPOSE_ENV) --env-file compose/images.lock.env -f compose/docker-compose.yml -f compose/docker-compose.pumba.yml --profile pumba
COMPOSE_KEEPALIVED = docker compose --env-file $(COMPOSE_ENV) --env-file compose/images.lock.env -f compose/docker-compose.yml -f compose/docker-compose.keepalived.yml --profile keepalived

RUN_ID ?= $(shell date -u +%Y%m%dT%H%M%SZ)
TEST_RUNNER_IMAGE ?= python:3.12-slim

.PHONY: ensure-env lock-images up down restart ps logs init verify test test-sanity test-sanity-cov coverage-badge \
	chaos-primary-kill chaos-etcd-quorum chaos-primary-etcd-partition chaos-replica-lag chaos-archive-break \
	pitr-backup pitr-restore evidence-clean ci-smoke compose-config

ensure-env:
	@if [ ! -f .env ]; then cp .env.example .env; fi

lock-images:
	@bash scripts/lock-images.sh

up: ensure-env
	$(COMPOSE_BASE) up -d --build

restart:
	$(COMPOSE_BASE) restart

down:
	$(COMPOSE_BASE) down --remove-orphans

ps:
	$(COMPOSE_BASE) ps

logs:
	$(COMPOSE_BASE) logs --tail 200

init: ensure-env
	@bash scripts/init.sh

verify: ensure-env
	@RUN_ID=$(RUN_ID) bash scripts/evidence.sh

test: ensure-env
	$(COMPOSE_BASE) --profile test run --rm test-runner

test-sanity:
	docker run --rm -v "$(PWD):/workspace" -w /workspace $(TEST_RUNNER_IMAGE) bash -lc "pip install --no-cache-dir -r tests/requirements.txt && pytest -q -k sanity tests/sanity"

test-sanity-cov:
	@mkdir -p artifacts/coverage
	docker run --rm -v "$(PWD):/workspace" -w /workspace $(TEST_RUNNER_IMAGE) bash -lc "pip install --no-cache-dir -r tests/requirements.txt && pytest -q -k sanity --cov=tests --cov-report=term-missing --cov-report=xml:artifacts/coverage/coverage.xml tests/sanity"

coverage-badge:
	@mkdir -p artifacts/coverage docs/badges
	docker run --rm -v "$(PWD):/workspace" -w /workspace $(TEST_RUNNER_IMAGE) bash -lc "pip install --no-cache-dir -r tests/requirements.txt anybadge==1.16.0 && pytest -q -k sanity --cov=tests --cov-report=xml:artifacts/coverage/coverage.xml tests/sanity && COV_PCT=\$$(python -c \"import xml.etree.ElementTree as ET; r=ET.parse('artifacts/coverage/coverage.xml').getroot(); print(round(float(r.attrib.get('line-rate', 0.0))*100, 2))\") && anybadge --label=coverage --value=\$${COV_PCT} --file=docs/badges/coverage.svg --suffix='%' 50=red 70=orange 80=yellow 90=green"

chaos-primary-kill: ensure-env
	@RUN_ID=$(RUN_ID) bash chaos/scripts/chaos-primary-kill.sh

chaos-etcd-quorum: ensure-env
	@RUN_ID=$(RUN_ID) bash chaos/scripts/chaos-etcd-quorum.sh

chaos-primary-etcd-partition: ensure-env
	@RUN_ID=$(RUN_ID) bash chaos/scripts/chaos-primary-etcd-partition.sh

chaos-replica-lag: ensure-env
	@RUN_ID=$(RUN_ID) bash chaos/scripts/chaos-replica-lag.sh

chaos-archive-break: ensure-env
	@RUN_ID=$(RUN_ID) bash chaos/scripts/chaos-archive-break.sh

pitr-backup: ensure-env
	@RUN_ID=$(RUN_ID) bash pgbackrest/scripts/full-backup.sh

pitr-restore: ensure-env
	@RUN_ID=$(RUN_ID) bash pgbackrest/scripts/pitr-restore.sh

evidence-clean:
	rm -rf artifacts/*

compose-config: ensure-env
	$(COMPOSE_BASE) config > /dev/null
	$(COMPOSE_PUMBA) config > /dev/null
	$(COMPOSE_KEEPALIVED) config > /dev/null

ci-smoke: compose-config
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -e SC1091 chaos/scripts/*.sh pgbackrest/scripts/*.sh scripts/*.sh scripts/lib/*.sh; \
	else \
		echo "shellcheck nao encontrado, pulando"; \
	fi
	@if command -v yamllint >/dev/null 2>&1; then \
		yamllint compose observability .github/workflows; \
	else \
		echo "yamllint nao encontrado, pulando"; \
	fi
	docker run --rm -v "$(PWD):/workspace" -w /workspace $(TEST_RUNNER_IMAGE) bash -lc "pip install --no-cache-dir -r tests/requirements.txt && pytest -q -k sanity tests/sanity"
