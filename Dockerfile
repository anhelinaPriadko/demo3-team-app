FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app

COPY pom.xml .
COPY src ./src

ENV MAVEN_OPTS="-Xmx768m"

RUN mvn -B -ntp clean package -DskipTests

FROM eclipse-temurin:21-jre

WORKDIR /app

ARG OTEL_JAVA_AGENT_VERSION=2.33.1

ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar

RUN chmod 644 /opt/opentelemetry-javaagent.jar

COPY --from=builder /app/target/*.jar /app/app.jar

ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/opentelemetry-javaagent.jar"

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]