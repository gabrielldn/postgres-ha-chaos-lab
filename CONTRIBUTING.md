# Contribuindo

## Fluxo de contribuição

1. Crie uma branch a partir de `main`.
2. Faça mudanças pequenas e focadas.
3. Execute os checks locais mínimos.
4. Abra PR para `main` com evidências objetivas.

## Checks mínimos antes do PR

1. Validar smoke + sanity:

```bash
make ci-smoke
```

2. Se alterou scripts de caos, failover ou DR:

```bash
make up
make init
make chaos-primary-kill
make verify
make down
```

3. Se alterou backup/PITR:

```bash
make up
make init
make pitr-restore
make verify
make down
```

## Padrão de commits

Use Conventional Commits:

- `feat:` nova funcionalidade.
- `fix:` correção de bug.
- `docs:` documentação.
- `test:` testes.
- `ci:` workflow/pipeline.
- `chore:` manutenção sem mudança funcional.

Exemplos:

- `feat(chaos): add client-side proof for RO endpoint`
- `fix(tests): remove docker compose dependency from e2e runner`
- `docs(adr): document local TLS tradeoff`

## Como adicionar um novo cenário de caos

1. Crie `chaos/scripts/chaos-<cenario>.sh`.
2. Use `scripts/lib/run_id.sh` e grave artefatos em `artifacts/${RUN_ID}/...`.
3. Gere evidência objetiva com `result.json` (status, timestamps, métricas e assertivas).
4. Adicione alvo no `Makefile` (`make chaos-<cenario>`).
5. Atualize `scripts/evidence.sh` para consolidar a saída no `SUMMARY.md`.
6. Documente em `runbooks/` e, se houver decisão de arquitetura, crie ADR em `docs/adr/`.
7. Atualize `README.md` com contrato e critérios de aceite do cenário.

## Padrão esperado no PR

Inclua:

1. Contexto do problema.
2. O que mudou (arquivos principais).
3. Evidências executadas (comandos + resultado).
4. Riscos/rollback.

## Processo de release (maintainers)

1. Garanta `main` verde (`smoke`).
2. Crie tag semântica:

```bash
git tag v1.0.0
git push origin v1.0.0
```

3. O workflow `.github/workflows/release.yml` publica:
- Release no GitHub com assets de referência.
- Imagem `postgres-ha-chaos-lab-pg` no GHCR.
