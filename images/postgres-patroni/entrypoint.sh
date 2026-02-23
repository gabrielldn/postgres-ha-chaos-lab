#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  set -- patroni
fi

if [[ "$1" != "patroni" ]]; then
  exec "$@"
fi

: "${PATRONI_NAME:?PATRONI_NAME is required}"
: "${PATRONI_SCOPE:?PATRONI_SCOPE is required}"
: "${ETCD_HOSTS:?ETCD_HOSTS is required}"
: "${PG_SUPERUSER:?PG_SUPERUSER is required}"
: "${PG_SUPERPASS:?PG_SUPERPASS is required}"
: "${PG_APP_DB:?PG_APP_DB is required}"
: "${PG_APP_USER:?PG_APP_USER is required}"
: "${PG_APP_PASS:?PG_APP_PASS is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"
: "${BACKREST_STANZA:?BACKREST_STANZA is required}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${MINIO_BUCKET:?MINIO_BUCKET is required}"

mkdir -p /etc/patroni /etc/pgbackrest /var/log/pgbackrest /var/lib/postgresql/data /tmp/pgbackrest
chmod 700 /var/lib/postgresql/data

cat > /etc/pgbackrest/pgbackrest.conf <<CONF
[global]
repo1-type=s3
repo1-path=/pgbackrest
repo1-s3-uri-style=path
repo1-s3-endpoint=http://minio:9000
repo1-s3-bucket=${MINIO_BUCKET}
repo1-s3-region=us-east-1
repo1-s3-key=${MINIO_ROOT_USER}
repo1-s3-key-secret=${MINIO_ROOT_PASSWORD}
repo1-s3-verify-tls=n
start-fast=y
process-max=2
archive-async=n
log-level-console=info
log-level-file=detail

[${BACKREST_STANZA}]
pg1-path=/var/lib/postgresql/data
pg1-port=5432
pg1-user=postgres
CONF

envsubst < /opt/patroni/patroni.yml.tmpl > /etc/patroni/patroni.yml

chown -R postgres:postgres /etc/patroni /etc/pgbackrest /var/log/pgbackrest /var/lib/postgresql /tmp/pgbackrest

exec gosu postgres patroni /etc/patroni/patroni.yml
