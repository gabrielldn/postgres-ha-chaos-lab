#!/usr/bin/env python3
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import psycopg

DSN = os.getenv("EXPORTER_DSN", "postgresql://postgres:postgres@pg1:5432/postgres?sslmode=disable")
LISTEN_HOST = os.getenv("EXPORTER_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("EXPORTER_PORT", "9188"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        archived = 0
        failed = 0
        age_seconds = -1.0
        check_success = 0

        try:
            with psycopg.connect(DSN, connect_timeout=2) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        SELECT archived_count,
                               failed_count,
                               EXTRACT(EPOCH FROM (now() - COALESCE(last_archived_time, now())))
                        FROM pg_stat_archiver
                        """
                    )
                    row = cur.fetchone()
                    if row:
                        archived, failed, age_seconds = row
                        check_success = 1
        except Exception:
            check_success = 0

        payload = "\n".join(
            [
                "# HELP pgbackrest_check_success 1 quando coleta de archiver funciona",
                "# TYPE pgbackrest_check_success gauge",
                f"pgbackrest_check_success {check_success}",
                "# HELP pg_archiver_archived_count Total de WALs arquivados",
                "# TYPE pg_archiver_archived_count counter",
                f"pg_archiver_archived_count {archived}",
                "# HELP pg_archiver_failed_count Total de WALs com falha no archive",
                "# TYPE pg_archiver_failed_count counter",
                f"pg_archiver_failed_count {failed}",
                "# HELP pg_archiver_last_archived_age_seconds Idade do ultimo WAL arquivado",
                "# TYPE pg_archiver_last_archived_age_seconds gauge",
                f"pg_archiver_last_archived_age_seconds {age_seconds}",
                "",
            ]
        ).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        return


def main():
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"backrest-exporter listening on {LISTEN_HOST}:{LISTEN_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
