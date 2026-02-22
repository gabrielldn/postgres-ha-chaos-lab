FROM postgres:17-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    curl \
    gettext-base \
    iproute2 \
    iptables \
    jq \
    pgbackrest \
    python3 \
    python3-pip \
    procps \
  && rm -rf /var/lib/apt/lists/*

COPY images/postgres-patroni/requirements.lock.txt /tmp/requirements.lock.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements.lock.txt

COPY images/postgres-patroni/entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh

ENTRYPOINT ["lab-entrypoint.sh"]
CMD ["patroni"]
