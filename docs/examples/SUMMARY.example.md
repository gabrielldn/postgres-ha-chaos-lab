# SUMMARY (exemplo)

> Artefato de exemplo para release (`vX.Y.Z`), gerado a partir de `scripts/evidence.sh`.

## Identificação

- `run_id`: `20260222T203500Z`
- `profile`: `default`
- `environment`: `Linux Ubuntu 24.04+ local`

## Estado do cluster

- `cluster`: `ha-lab`
- `leader_before`: `pg1`
- `leader_after`: `pg2`
- `single_leader_assert`: `pass`
- `split_brain_assert`: `pass`

## RTO (failover primário)

- `t0_kill_utc`: `2026-02-22T20:35:12Z`
- `t1_first_rw_commit_utc`: `2026-02-22T20:35:20Z`
- `rto_ms`: `8042`
- `FAILOVER_SLO_MS`: `15000`
- `rto_slo_pass`: `true`

## Quorum etcd

- `quorum_lost`: `true`
- `leader_promotion_blocked`: `true`
- `etcd_health_evidence`: `capturada`

## RO + lag

- `degraded_replica_removed_from_ro`: `true`
- `client_side_ro_proof`: `capturada`

## PITR

- `restore_point`: `rp_lab_20260222_2037`
- `marker_before_exists`: `true`
- `marker_after_exists`: `false`
- `timeline`: `capturada`
- `pitr_assert`: `pass`

## Backup e archive

- `pgbackrest_info`: `ok`
- `pgbackrest_check`: `ok`
- `wal_archive_delay_alert`: `false`

## Alertas (Prometheus)

- `PatroniPrimaryUnavailable`: `inactive`
- `FailoverDetected`: `active_durante_caos`
- `ReplicaLagHigh`: `active_durante_lag`
- `PgbackrestCheckFailed`: `inactive`

## Links internos

- Arquitetura: `docs/arquitetura.md`
- ADR checks REST: `docs/adr/0001-haproxy-rest-checks.md`
- ADR pinagem de imagem: `docs/adr/0002-image-locking.md`
- ADR caos de rede: `docs/adr/0003-chaos-network.md`
- ADR TLS local: `docs/adr/0004-tls-local-tradeoff.md`
- Runbooks: `runbooks/README.md`
