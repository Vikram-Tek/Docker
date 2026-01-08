# Multi-stage build for Spring Pet Clinic Application
FROM eclipse-temurin:17-jdk-alpine AS build

# Install build tools and utilities
RUN apk add --no-cache \
    curl \
    wget \
    git \
    bash \
    tar \
    gzip \
    ca-certificates \
    openssl

# Set build environment variables
ENV MAVEN_OPTS="-Xmx1024m" \
    JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom" \
    BUILD_DATE="2024-01-01" \
    APP_VERSION="4.0.0-SNAPSHOT"

# Set working directory
WORKDIR /app

# Copy Maven wrapper and pom.xml first for better layer caching
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .

# Make Maven wrapper executable
RUN chmod +x ./mvnw

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN ./mvnw dependency:go-offline -B

# Copy additional configuration files
COPY *.properties . 2>/dev/null || true
COPY *.yml . 2>/dev/null || true

# Copy source code
COPY src src

# Run code analysis
RUN ./mvnw compile -B
RUN ./mvnw test-compile -B

# Build the application
RUN ./mvnw clean package -DskipTests -B

# Create build information
RUN echo "Build Date: $(date)" > build-info.txt && \
    echo "Java Version: $(java -version 2>&1 | head -n 1)" >> build-info.txt && \
    echo "Maven Version: $(./mvnw --version | head -n 1)" >> build-info.txt

# Runtime stage
FROM eclipse-temurin:17-jre-alpine AS runtime

# Install runtime utilities
RUN apk add --no-cache \
    curl \
    wget \
    bash \
    dumb-init \
    tzdata \
    ca-certificates \
    jq \
    netcat-openbsd \
    procps \
    htop && \
    rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Create application directories
RUN mkdir -p /app/logs /app/config /app/data /app/scripts

# Create non-root user for security
RUN addgroup -g 1001 -S spring && \
    adduser -u 1001 -S spring -G spring -h /app -s /bin/bash

# Set working directory
WORKDIR /app

# Copy the built JAR from build stage
COPY --from=build --chown=spring:spring /app/target/*.jar app.jar
COPY --from=build --chown=spring:spring /app/build-info.txt .

# Create application configuration
RUN echo 'server.port=8080' > /app/config/application.properties && \
    echo 'management.endpoints.web.exposure.include=health,info,metrics' >> /app/config/application.properties && \
    echo 'management.endpoint.health.show-details=always' >> /app/config/application.properties && \
    echo 'logging.file.name=/app/logs/application.log' >> /app/config/application.properties && \
    echo 'logging.level.org.springframework.samples.petclinic=INFO' >> /app/config/application.properties

# Create database-specific configurations
RUN echo 'spring.datasource.url=jdbc:mysql://mysql:3306/petclinic' > /app/config/application-mysql.properties && \
    echo 'spring.datasource.username=petclinic' >> /app/config/application-mysql.properties && \
    echo 'spring.datasource.password=petclinic' >> /app/config/application-mysql.properties

RUN echo 'spring.datasource.url=jdbc:postgresql://postgres:5432/petclinic' > /app/config/application-postgres.properties && \
    echo 'spring.datasource.username=petclinic' >> /app/config/application-postgres.properties && \
    echo 'spring.datasource.password=petclinic' >> /app/config/application-postgres.properties

# Create startup script
RUN echo '#!/bin/bash' > /app/scripts/startup.sh && \
    echo 'set -e' >> /app/scripts/startup.sh && \
    echo 'echo "Starting PetClinic Application..."' >> /app/scripts/startup.sh && \
    echo 'echo "Date: $(date)"' >> /app/scripts/startup.sh && \
    echo 'echo "Java Version: $(java -version 2>&1 | head -n 1)"' >> /app/scripts/startup.sh && \
    echo 'echo "Memory: $(free -h | grep Mem | awk "{print \$2}")"' >> /app/scripts/startup.sh && \
    echo 'mkdir -p /app/logs' >> /app/scripts/startup.sh && \
    echo 'exec java $JAVA_OPTS -jar app.jar "$@"' >> /app/scripts/startup.sh && \
    chmod +x /app/scripts/startup.sh

# Create monitoring script
RUN echo '#!/bin/bash' > /app/scripts/monitor.sh && \
    echo 'while true; do' >> /app/scripts/monitor.sh && \
    echo '  echo "$(date): Memory: $(free -m | grep Mem | awk "{print \$3/\$2*100}")%" >> /app/logs/monitor.log' >> /app/scripts/monitor.sh && \
    echo '  sleep 60' >> /app/scripts/monitor.sh && \
    echo 'done' >> /app/scripts/monitor.sh && \
    chmod +x /app/scripts/monitor.sh

# Create health check script
RUN echo '#!/bin/bash' > /app/scripts/health.sh && \
    echo 'curl -f http://localhost:8080/actuator/health || wget --spider http://localhost:8080/actuator/health' >> /app/scripts/health.sh && \
    chmod +x /app/scripts/health.sh

# Change ownership to spring user
RUN chown -R spring:spring /app && \
    chmod 644 /app/app.jar

# Switch to non-root user
USER spring

# Set runtime environment variables
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC -Djava.security.egd=file:/dev/./urandom -Dspring.config.additional-location=/app/config/" \
    SPRING_PROFILES_ACTIVE="default" \
    SERVER_PORT=8080 \
    LOG_LEVEL="INFO" \
    APP_NAME="petclinic"

# Expose ports
EXPOSE 8080 8081

# Add metadata labels
LABEL maintainer="Spring PetClinic Team" \
      version="4.0.0-SNAPSHOT" \
      description="Spring PetClinic Sample Application" \
      org.opencontainers.image.title="Spring PetClinic" \
      org.opencontainers.image.version="4.0.0-SNAPSHOT" \
      org.opencontainers.image.vendor="Spring" \
      application.framework="Spring Boot" \
      application.language="Java"

# Create volumes for persistent data
VOLUME ["/app/logs", "/app/data"]

# Enhanced health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /app/scripts/health.sh

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Run the application
CMD ["/app/scripts/startup.sh"]
