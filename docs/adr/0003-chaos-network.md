# ADR 0003 - Estratégia de caos de rede

## Status
Aceito

## Decisão
- `toxiproxy` permanece no perfil padrão para experimentos determinísticos TCP.
- Cenários críticos do lab usam isolamento de rede determinístico com `iptables` nos nós PG.
- `pumba` fica em profile opcional para cenários avançados de partição/latência entre containers.

## Motivação
Equilíbrio entre previsibilidade em ambiente local e cobertura de cenários avançados.
