# Runbook: PITR em restore dedicado

## Fluxo
1. Inserir `marker_before`.
2. Criar restore point.
3. Inserir `marker_after`.
4. Executar restore por nome em instância dedicada (`15434`).
5. Validar: before existe e after não existe.

## Comandos
- `make pitr-backup`
- `make pitr-restore`

## Evidência
`artifacts/<RUN_ID>/pitr/result.json`
