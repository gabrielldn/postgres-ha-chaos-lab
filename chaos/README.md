# Chaos scenarios

Scripts disponíveis:
- `chaos-primary-kill.sh`
- `chaos-etcd-quorum.sh`
- `chaos-primary-etcd-partition.sh`
- `chaos-replica-lag.sh`
- `chaos-archive-break.sh`

Todos gravam evidência em `artifacts/<RUN_ID>/chaos/<cenario>/`.
Contrato de execução: cada cenário gera `result.json` e retorna `exit 1` quando os critérios de aceite não são atendidos.
