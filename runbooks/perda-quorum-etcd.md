# Runbook: Perda de quorum etcd

## Sintoma
Sem promoção de líder após queda do primário.

## Comportamento esperado
Sem quorum no DCS, Patroni prioriza safety e não promove novo líder.

## Verificações
1. `etcdctl endpoint health --cluster`
2. `etcdctl endpoint status --cluster`
3. `patronictl list`
4. endpoints `/primary` nos nós

## Recuperação
1. Subir ao menos 2 nós etcd.
2. Aguardar retorno de quorum.
3. Validar eleição normal e endpoint RW.

## Evidência
`artifacts/<RUN_ID>/chaos/etcd-quorum/`
