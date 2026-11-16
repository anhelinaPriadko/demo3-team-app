# Nginx exporter prerequisite

Collector scrapes `127.0.0.1:9113/metrics`. Nginx owner must enable a localhost-only `stub_status` location, e.g. `location = /nginx_status { stub_status; allow 127.0.0.1; deny all; }`, validate/reload Nginx, install and pin `nginx-prometheus-exporter`, bind it to `127.0.0.1:9113`, and configure it to scrape `http://127.0.0.1/nginx_status`. Verify with `curl -fsS http://127.0.0.1:9113/metrics`. Do not expose status endpoint or port 9113 publicly. Exporter binary/version and systemd unit are owned by Nginx/infrastructure owner.
