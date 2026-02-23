# Arquitetura do postgres-ha-chaos-lab

## Objetivo
Ambiente 100% local (Linux Ubuntu 24.04+ nativo ou WSL2 + Docker Compose) para demonstrar HA/DR/Chaos em Postgres com evidência prática.

## Topologia visual (Mermaid)

```mermaid
flowchart LR
  C[Cliente SQL]
  RW[HAProxy RW :5432]
  RO[HAProxy RO :5433]
  S[HAProxy Stats :8404]

  subgraph PG["Postgres + Patroni"]
    PG1[pg1 :5432/:8008]
    PG2[pg2 :5432/:8008]
    PG3[pg3 :5432/:8008]
  end

  subgraph DCS["etcd quorum (3 nós)"]
    E1[etcd1 :2379]
    E2[etcd2 :2379]
    E3[etcd3 :2379]
  end

  subgraph DR["Backup/Restore"]
    B[pgBackRest]
    M[MinIO S3 local]
    R[restore :15434]
  end

  subgraph OBS["Observabilidade"]
    PE[postgres_exporter]
    NE[node_exporter]
    P[Prometheus :9090]
    G[Grafana :3000]
  end

  C --> RW
  C --> RO
  C --> S
  RW --> PG1
  RW --> PG2
  RW --> PG3
  RO --> PG1
  RO --> PG2
  RO --> PG3

  PG1 --> E1
  PG1 --> E2
  PG1 --> E3
  PG2 --> E1
  PG2 --> E2
  PG2 --> E3
  PG3 --> E1
  PG3 --> E2
  PG3 --> E3

  PG1 --> B
  PG2 --> B
  PG3 --> B
  B --> M
  M --> R

  PG1 --> PE
  PG2 --> PE
  PG3 --> PE
  PE --> P
  NE --> P
  P --> G
```

## Componentes
- `pg1`, `pg2`, `pg3`: Postgres 17 com Patroni.
- `etcd1..3`: DCS do Patroni para eleição e lock de líder.
- `haproxy`: endpoint único RW (`15432`) e RO (`15433`) via checks REST do Patroni.
- `minio`: S3 local para repositório pgBackRest.
- `pgbackrest`: backup/WAL archive e PITR.
- `prometheus` + `grafana`: métricas, regras e dashboards.
- `toxiproxy` + perfil `pumba` + isolamento seletivo via `iptables` nos nós PG: simulação de falhas de rede e caos controlado.

## Fluxo de escrita
1. Cliente escreve em `localhost:15432`.
2. HAProxy envia apenas para nó que responde `200` em `/primary`.
3. Patroni mantém lock no etcd para evitar dual-primary.
4. Em falha do primário, a escrita só volta após eleição e commit bem-sucedido via RW.

## Fluxo de leitura
1. Cliente lê de `localhost:15433`.
2. HAProxy envia apenas para nós que respondem `200` em `/replica?lag=...`.
3. Réplicas fora do limite de lag saem do balanceamento.

## Evidências
Todos os cenários escrevem artefatos em `artifacts/<RUN_ID>/`.
`make verify` consolida em `SUMMARY.md` + `.zip`.
