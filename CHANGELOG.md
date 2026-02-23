# Changelog

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

Formato inspirado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e versionamento semântico.

## [1.0.1] - 2026-02-23

### Destaques
- Alinhamento do repositório com histórico de commits atômico e semântico no `main`.
- Fortalecimento dos contratos de caos, CI E2E e sanity checks funcionais.

### Added
- Job E2E no CI (`smoke.yml`) com `make up`, `make init` e `make test`.
- Runbook dedicado para partição entre primário e etcd.
- Sanity checks de contrato:
  - scripts de caos devem gerar `result.json` e falhar com `exit 1` em violação;
  - targets de caos no `Makefile`;
  - uso de `set -euo pipefail` em scripts shell;
  - presença de job E2E no workflow de smoke.

### Changed
- Cenário `chaos-primary-etcd-partition` migrado para partição determinística via `iptables` (mais estável no ambiente local) com assertivas explícitas de safety e recuperação.
- `SUMMARY.md` consolidado inclui resultado de `primary-etcd-partition`.
- Documentação operacional atualizada para refletir estratégia de rede determinística (`iptables`) e papel opcional do Pumba.

### Fixed
- Removida inconsistência de engenharia no cenário `primary-etcd-partition`, que antes não possuía critério de aceite automatizado.
- Fechado gap de pipeline onde E2E não era executado em CI.

## [1.0.0] - 2026-02-23

### Destaques
- Laboratório HA/DR/Chaos completo e reproduzível para PostgreSQL 17 com Patroni.
- Evidência operacional consolidada via `scripts/evidence.sh` com `RUN_ID` único por execução.
- Cenários de caos com provas objetivas (RTO, quorum, lag de réplica e PITR).

### Added
- Stack principal com `Postgres + Patroni + etcd(3) + HAProxy + pgBackRest + MinIO + Prometheus + Grafana + Toxiproxy`.
- Fluxo de PITR dedicado com marcadores before/after, validação de timeline e resultado estruturado.
- Evidence pack completo em `artifacts/<RUN_ID>/` com `SUMMARY.md` e pacote `.zip`.
- `CONTRIBUTING.md` com padrão de commits, checks e fluxo para novos cenários de caos.
- Workflow de release em `.github/workflows/release.yml` para publicar imagem custom no GHCR e assets de release.
- Exemplo de summary para release em `docs/examples/SUMMARY.example.md`.
- Diagrama visual de arquitetura em Mermaid em `docs/arquitetura.md`.
- ADR `0004-tls-local-tradeoff.md` registrando decisão consciente de TLS desabilitado no perfil local.

### Changed
- Testes E2E executam 100% containerizados, sem dependência de `docker compose` dentro do test-runner.
- Alerta e dashboard de lag ajustados para métrica real do exporter (`pg_stat_replication_pg_wal_lsn_diff`).
- README atualizado para padrão de documentação com badges de CI, release, GHCR e cobertura.
- Smoke CI ampliado para publicar artefato de cobertura (`coverage.xml`).

### Fixed
- Correção do `make test` no `test-runner` (execução correta do comando com `bash -lc`).
- Remoção de scrape inválido do HAProxy (`/metrics`) no Prometheus para evitar target DOWN falso.

### Segurança e trade-offs
- Credenciais de laboratório mantidas como placeholders (`dummy-*`) em `.env.example`.
- Decisão de simplificação local sem TLS interno documentada com requisitos explícitos para produção.

### Observações de release
- Esta release estabelece o baseline estável do projeto para demonstrações de senioridade em HA/DR/Chaos.
- Para ambientes de produção, aplicar hardening adicional (TLS/mTLS, gestão de segredos e políticas de acesso).
