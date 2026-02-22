# ADR 0001 - HAProxy decide primário/réplica via REST do Patroni

## Status
Aceito

## Contexto
`pgsql-check` valida apenas disponibilidade TCP/SQL, mas não distingue com precisão papel de líder e atraso de réplica em cenários de failover/lag.

## Decisão
HAProxy usa health checks HTTP no Patroni:
- RW: `GET /primary`
- RO: `GET /replica?lag=<bytes>`

## Consequências
- Separação explícita de tráfego RW/RO.
- Réplica atrasada removida automaticamente do backend RO.
- Melhor evidência operacional para cenários de caos.
