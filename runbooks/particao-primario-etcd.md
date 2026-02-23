# Runbook: Partição primário x etcd

## Sintoma
Oscilação de escrita no endpoint RW durante falha de rede no nó primário.

## Comportamento esperado
- Primário perde lock no DCS e deixa de aceitar escrita.
- Não ocorre dual-primary (split-brain).
- RW volta após nova liderança ou recuperação segura do lock.

## Verificações
1. `patronictl list` e contagem de líderes.
2. Endpoints `/primary` em `18081/18082/18083`.
3. Probes RW no artefato `rw-probe.csv`.
4. `primary-count.csv` para confirmar que nunca houve mais de 1 primário.

## Recuperação
1. Remover partição de rede.
2. Validar líder único.
3. Validar escrita via endpoint RW.

## Evidência
`artifacts/<RUN_ID>/chaos/primary-etcd-partition/result.json`
