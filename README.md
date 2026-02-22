# Postgres HA Chaos Lab

[![Licença MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-yellow.svg)](LICENSE)
![WSL2 Ubuntu 24.04+](https://img.shields.io/badge/WSL2-Ubuntu%2024.04%2B-E95420?logo=ubuntu&logoColor=white)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white)
![Patroni 4.0.4](https://img.shields.io/badge/Patroni-4.0.4-1F5E99)
![etcd quorum 3](https://img.shields.io/badge/etcd-quorum%203-419EDA)
![Smoke CI](https://img.shields.io/github/actions/workflow/status/gabrielldn/postgres-ha-chaos-lab/smoke.yml?label=Smoke%20CI)

Laboratório local `production-like` para validar e demonstrar HA/DR/Chaos em PostgreSQL com evidência prática reproduzível em WSL2.

## Objetivo do projeto

Entregar um ambiente reproduzível para praticar e demonstrar:

- Alta disponibilidade com eleição automática e failover seguro.
- Disaster Recovery com backup contínuo, WAL archive e PITR dedicado.
- Testes de caos determinísticos (primário, quorum etcd, partição e lag de réplica).
- Observabilidade operacional com métricas e alertas.
- Geração de evidence pack único por execução (`RUN_ID`).

## Stack principal

- Banco: PostgreSQL 17 + Patroni (`pg1`, `pg2`, `pg3`).
- DCS: etcd com 3 nós (`etcd1`, `etcd2`, `etcd3`).
- Roteamento: HAProxy com checks REST do Patroni (`/primary`, `/replica?lag=`).
- DR: pgBackRest com MinIO (S3 local) para backup e archive.
- Observabilidade: Prometheus + Grafana + exporters.
- Chaos: Toxiproxy e Pumba (profile opcional).
- Prova de lag RO: isolamento de replicação via `iptables` no cenário `chaos-replica-lag`.

## Topologia resumida

- Endpoint RW: `localhost:15432`
- Endpoint RO: `localhost:15433`
- Restore PITR dedicado: `localhost:15434`
- Patroni REST: `localhost:18081`, `localhost:18082`, `localhost:18083`
- HAProxy stats: `localhost:18404/stats`
- MinIO API/Console: `localhost:19000` / `localhost:19001`
- Prometheus: `localhost:19090`
- Grafana: `localhost:13001`
- Toxiproxy API: `localhost:18474`

## Contratos do repositório

- Operação: `Makefile` (`make up`, `make init`, `make verify`, `make chaos-*`, `make pitr-restore`).
- Reprodutibilidade de imagens externas: `compose/images.lock.env` (`make lock-images`).
- Configuração Patroni: `patroni/patroni.yml.tmpl`.
- Configuração de proxy e checks: `haproxy/haproxy.cfg`.
- Scripts de caos: `chaos/scripts/`.
- Scripts de backup/PITR: `pgbackrest/scripts/`.
- Evidence owner único: `scripts/evidence.sh`.
- Governança técnica: `docs/adr/`, `runbooks/`, `.github/workflows/smoke.yml`.

## Começando rápido (fluxo recomendado)

1. Criar variáveis locais:

```bash
cp .env.example .env
```

2. Travar digests de imagens externas (recomendado):

```bash
make lock-images
```

3. Subir stack:

```bash
make up
```

4. Inicializar cluster e pgBackRest:

```bash
make init
```

5. Gerar evidence pack inicial:

```bash
make verify
```

## Comandos `make`

- `make up`: sobe stack base.
- `make down`: derruba stack.
- `make ps` / `make logs`: status e logs.
- `make init`: inicialização da base, usuários e pgBackRest.
- `make verify`: coleta evidências consolidadas.
- `make chaos-primary-kill`: valida failover com medição de RTO real.
- `make chaos-etcd-quorum`: valida safety com perda de quorum.
- `make chaos-primary-etcd-partition`: simula partição entre primário e etcd.
- `make chaos-replica-lag`: prova exclusão de réplica degradada no endpoint RO.
- `make chaos-archive-break`: valida falha esperada no archive.
- `make pitr-backup` / `make pitr-restore`: backup e prova PITR.
- `make ci-smoke`: `compose config` + lint + `pytest -k sanity`.

## Evidência e SLO

- `RUN_ID` único UTC: `YYYYMMDDTHHMMSSZ`.
- Todos os artefatos em `artifacts/<RUN_ID>/`.
- Consolidado único em `artifacts/<RUN_ID>/SUMMARY.md` (gerado por `scripts/evidence.sh`).
- Snapshot de versões reais no evidence pack:
  - `postgres --version`
  - `patroni --version`
  - `etcd --version`
  - `haproxy -v`
  - `pgbackrest version`
  - `docker image ls` filtrado para imagens do lab
- SLO de failover: `FAILOVER_SLO_MS` em `.env` (default `15000`).
- Assert de failover: `make chaos-primary-kill` falha se `rto_ms > FAILOVER_SLO_MS`.
- Medição de RTO:
  - `t0`: instante do kill do primário
  - `t1`: primeira escrita commitada via endpoint RW

## Documentação

- Índice da documentação: `docs/README.md`
- Arquitetura: `docs/arquitetura.md`
- Troubleshooting: `docs/troubleshooting.md`
- ADRs: `docs/adr/`
- Runbooks: `runbooks/README.md`

## Observações práticas

- `keepalived` é profile opcional/experimental em WSL.
- O cenário `chaos-primary-kill` pode violar SLO agressivo em hosts locais com contenção de recursos.
- O critério de sucesso principal é segurança (sem split-brain) + evidência reproduzível.
