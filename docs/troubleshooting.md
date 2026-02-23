# Troubleshooting

## `make up` falha no build da imagem custom
- Verifique acesso à internet para `apt` e `pip`.
- Execute `docker system prune` se houver cache corrompido.

## Endpoint RW/RO não responde
- `make ps`
- `curl http://127.0.0.1:18081/primary`
- `curl http://127.0.0.1:18404/stats`

## PITR falha
- Confirme bucket MinIO e `pgbackrest info`.
- Confira `artifacts/<RUN_ID>/pitr/restore.log`.

## Cenários com Pumba não executam
- Use Docker com permissão de socket (`/var/run/docker.sock`).
- Repare que `chaos-replica-lag` e `chaos-primary-etcd-partition` não dependem de Pumba (usam `iptables`).
- Pumba permanece profile opcional para cenários avançados de rede.
