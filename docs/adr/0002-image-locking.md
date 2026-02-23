# ADR 0002 - Pinagem de imagens por digest

## Status
Aceito

## Decisão
Imagens externas são travadas em `compose/images.lock.env` por digest via `make lock-images`.
Imagem custom local (`IMG_PG_PATRONI`) permanece fora do lock externo.

## Motivação
Garantir reprodutibilidade dos experimentos e evidências entre execuções.
