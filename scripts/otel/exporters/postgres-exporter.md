# PostgreSQL exporter prerequisite

Collector scrapes `127.0.0.1:9187/metrics` on BOTH DB VMs. DB owner must install/pin `postgres_exporter`, bind to localhost only, configure it to connect to local PostgreSQL, create a dedicated least-privilege monitoring role, and store credentials in a root-readable local env/secret file (never Git). Add a systemd unit and verify `curl -fsS http://127.0.0.1:9187/metrics`. Collector config contains no credentials. Confirm actual PostgreSQL log path and read permissions separately.
