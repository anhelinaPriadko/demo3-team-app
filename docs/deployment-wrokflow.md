## Deployment workflow

Commits are synchronized from GitHub to the self-hosted GitLab instance.

The pipeline validates Terraform configuration and generates an infrastructure
plan. Changes to the main branch require manual approval of terraform_apply.

After approval, the pipeline checks deployment readiness, builds a Docker image,
and deploys application instances sequentially behind Nginx. VM addresses are
obtained from Terraform outputs. Application VMs retrieve database credentials
from Google Secret Manager.

OpenTelemetry Collectors are deployed through a separate pipeline job.
The application image includes the OpenTelemetry Java Agent.

A manual rollback_application job restores the releases recorded before that
pipeline's deployment. Database schema changes are not rolled back.

Public API check:
https://cinema-service-team1.pp.ua/api/v1/movies