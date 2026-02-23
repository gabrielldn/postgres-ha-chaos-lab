# Documentação

Este diretório concentra os guias arquiteturais e operacionais do `postgres-ha-chaos-lab`.

## Índice

- `arquitetura.md`: visão dos componentes, fluxos RW/RO, contratos de HA e diagrama visual Mermaid.
- `troubleshooting.md`: diagnóstico rápido para erros comuns de operação local.
- `adr/`: registros de decisões arquiteturais (ADRs).

## Fluxo sugerido de leitura

1. Leia `../README.md` para entender escopo, contratos e fluxo de execução.
2. Leia `arquitetura.md` para entender os componentes e caminhos de tráfego.
3. Consulte `adr/` para contexto de decisões técnicas relevantes.
4. Use `../runbooks/README.md` para resposta operacional a incidentes simulados.
5. Em falhas locais, consulte `troubleshooting.md`.
6. Para padrão de colaboração e PR, consulte `../CONTRIBUTING.md`.
