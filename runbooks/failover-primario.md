# Runbook: Failover de primário

## Sintoma
Escritas falham no endpoint RW (`15432`).

## Verificações
1. `make ps`
2. `docker compose ... exec -T pg1 patronictl -c /etc/patroni/patroni.yml list`
3. `curl http://127.0.0.1:18081/primary` (e nós 18082/18083)
4. `curl http://127.0.0.1:18404/stats`

## Ação
1. Validar quorum etcd (`runbooks/perda-quorum-etcd.md`).
2. Se primário caiu, aguardar promoção automática.
3. Se sem promoção, recuperar nó e/ou etcd.

## Evidência
`artifacts/<RUN_ID>/chaos/primary-kill/result.json`
