# ADR 0004 - TLS interno no lab local

## Status
Aceito

## Contexto
Em produção, conexões entre componentes de controle e dados devem usar TLS/mTLS (ex.: Patroni↔etcd, clientes↔Postgres/HAProxy e APIs administrativas).  
No lab local o objetivo principal é reproduzir cenários de HA/DR/Chaos com baixa fricção operacional.

## Decisão
No perfil padrão local, TLS interno fica desabilitado por simplicidade e velocidade de setup.  
A ausência de TLS é um trade-off consciente para foco em:

- eleição e failover seguro;
- comprovação de safety (sem split-brain);
- backup/PITR e evidências reproduzíveis.

## Consequências

- Benefício: onboarding rápido e troubleshooting mais simples em ambiente local.
- Risco: topologia não representa hardening de transporte exigido em produção.
- Mitigação: manter este ADR explícito, com requisito de habilitar TLS/mTLS em ambientes reais.

## Requisito para produção
Antes de uso fora de laboratório, habilitar TLS em:

1. etcd (peer/client certs);
2. Patroni para DCS e API;
3. HAProxy frontends/backends;
4. conexões SQL cliente↔proxy↔Postgres;
5. componentes de backup/objeto quando aplicável.
