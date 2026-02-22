# Runbook: Quebra de archive/WAL

## Sintoma
`pgbackrest check` falha.

## Verificações
1. Status do MinIO (`minio`, `minio-init`).
2. `pgbackrest info` e `pgbackrest check` no primário.
3. Alertas em Prometheus/Grafana.

## Recuperação
1. Restaurar disponibilidade do MinIO/bucket.
2. Reexecutar `pgbackrest check`.
3. Validar retomada do `pg_stat_archiver`.

## Evidência
`artifacts/<RUN_ID>/chaos/archive-break/`
