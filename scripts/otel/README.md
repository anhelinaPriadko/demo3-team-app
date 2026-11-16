
# OpenTelemetry Deployment

## Purpose

This directory contains scripts and configurations for
deploying OpenTelemetry Collector Contrib on the six GCP
application VMs.

## Supported VMs

| VM | Role | Configuration |
|---|---|---|
| demo3-nginx | Nginx | nginx.yaml |
| demo3-app-1 | Java application | app.yaml |
| demo3-app-2 | Java application | app.yaml |
| demo3-db-master | PostgreSQL master | db-master.yaml |
| demo3-db-slave | PostgreSQL replica | db-slave.yaml |
| demo3-db-witness | etcd witness | witness.yaml |

## Requirements

- Ubuntu 24.04 LTS
- systemd
- amd64 or arm64 architecture
- Internet access for package download
- Administrative privileges for installation
- OpenTelemetry Collector Contrib package

## Scripts

- install.sh — installs Collector
- configure.sh — applies role-specific configuration
- verify.sh — verifies installation and service status
- uninstall.sh — removes the Collector package

## Installation

```bash
sudo bash install.sh
```

## Configuration

```bash
sudo bash configure.sh <role> <vm-name>
```

Example:

```bash
sudo bash configure.sh nginx demo3-nginx
```

## Verification

```bash
sudo bash verify.sh
```

## Logs

```bash
sudo journalctl -u otelcol-contrib -f
```

## Current export mode

The current configurations use the debug exporter.

Telemetry is written to the Collector service logs.

The OTLP exporter to SigNoz will be configured after
the monitoring backend is deployed.

## Limitations

- PostgreSQL-specific metrics are not configured yet.
- etcd-specific metrics are not configured yet.
- Nginx-specific metrics are not configured yet.
- Java Agent integration is a separate application deployment task.
- File permissions for service logs must be verified.
