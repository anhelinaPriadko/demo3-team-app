# Java Agent integration for application owner

1. Open the existing application Dockerfile. Add `java-agent.Dockerfile.snippet` in the FINAL/RUNTIME stage that contains the JRE and launches the Spring Boot JAR. Do not replace the Dockerfile.
2. Merge `java-agent.env.example` into the existing Java app service `environment:` in docker-compose or the team's actual deployment manifest. Do not create a new service.
3. The endpoint is SigNoz `10.10.0.118:4318` over the private VPN. It is intentionally NOT localhost: the Java process runs inside a container and localhost would refer to that container.
4. Confirm Java runtime compatibility and approve/pin agent version `2.33.1` before merge. Build/publish one new image and redeploy it to both app VMs.
5. Verify startup logs show Java Agent initialization and that service `demo3-java-app` appears in SigNoz with traces and runtime metrics. Logs export is disabled; log shipping is separate.
