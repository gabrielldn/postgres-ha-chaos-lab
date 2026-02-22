# ADR 0003 - Estratégia de caos de rede

## Status
Aceito

## Decisão
- `toxiproxy` permanece no perfil padrão para experimentos determinísticos TCP.
- `pumba` fica em profile opcional para partição/latência entre containers do cluster.

## Motivação
Equilíbrio entre previsibilidade em ambiente local e cobertura de cenários avançados.
