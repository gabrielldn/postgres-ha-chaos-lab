# postgres-ha-chaos-lab

Lab local (WSL + Docker Compose) para provar HA/DR/Chaos em Postgres com evidência prática.

## Stack
- Postgres 17 + Patroni (`pg1`, `pg2`, `pg3`)
- etcd 3 nós (`etcd1..3`)
- HAProxy com checks REST do Patroni (`/primary`, `/replica?lag=...`)
- pgBackRest + WAL archive em MinIO
- Prometheus + Grafana + exporters
- Chaos: Toxiproxy (default) + Pumba (profile opcional)
- `chaos-replica-lag`: isolamento de replicação por `iptables` para provar exclusão de réplica com lag no endpoint RO

## Portas
- RW: `localhost:15432`
- RO: `localhost:15433`
- PITR restore: `localhost:15434`
- HAProxy stats: `localhost:18404/stats`
- MinIO API/Console: `localhost:19000` / `localhost:19001`
- Prometheus: `localhost:19090`
- Grafana: `localhost:13001`
- Toxiproxy API: `localhost:18474`

## Quickstart
```bash
cp .env.example .env
make lock-images      # opcional, recomendado para travar digests
make up
make init
make verify
```

## Comandos principais
```bash
make up
make down
make ps
make logs
make verify
make test

make chaos-primary-kill
make chaos-etcd-quorum
make chaos-primary-etcd-partition
make chaos-replica-lag
make chaos-archive-break

make pitr-backup
make pitr-restore
```

## Contratos de evidência
- `RUN_ID` único UTC: `YYYYMMDDTHHMMSSZ`
- Artefatos em `artifacts/<RUN_ID>/`
- Consolidado único em `artifacts/<RUN_ID>/SUMMARY.md` (gerado por `scripts/evidence.sh`)
- Snapshot de versões reais no evidence pack:
  - `postgres --version`
  - `patroni --version`
  - `etcd --version`
  - `haproxy -v`
  - `pgbackrest version`
  - inventário de imagens (`docker image ls` filtrado)

## SLO de failover
- `FAILOVER_SLO_MS` em `.env` (default `15000`)
- `make chaos-primary-kill` falha se `rto_ms > FAILOVER_SLO_MS`
- RTO medido como:
  - `t0`: momento do kill do primário
  - `t1`: primeira escrita com sucesso via endpoint RW

## Perfis opcionais
- `pumba`: cenários de rede avançados
- `keepalived`: experimental no WSL

## Smoke CI local
```bash
make ci-smoke
```
Inclui:
- `docker compose config`
- `shellcheck`
- `yamllint`
- `pytest -k sanity`

## Runbooks e ADRs
- Runbooks: `runbooks/`
- ADRs: `docs/adr/`
