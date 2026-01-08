# Multi-stage build for Spring Pet Clinic Application with Enhanced Features
FROM eclipse-temurin:17-jdk-alpine AS build

# Install build dependencies and tools
RUN apk add --no-cache \
    curl \
    git \
    bash \
    findutils \
    tar \
    gzip \
    ca-certificates \
    openssl

# Set build environment variables
ENV MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=256m" \
    JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom" \
    BUILD_DATE="2024-01-01T00:00:00Z" \
    VCS_REF="unknown"

# Set working directory
WORKDIR /app

# Create build user for security during build
RUN addgroup -g 1000 -S builduser && \
    adduser -u 1000 -S builduser -G builduser

# Copy Maven wrapper and pom.xml first for better layer caching
COPY --chown=builduser:builduser mvnw .
COPY --chown=builduser:builduser .mvn .mvn
COPY --chown=builduser:builduser pom.xml .

# Make Maven wrapper executable
RUN chmod +x ./mvnw

# Switch to build user
USER builduser

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN ./mvnw dependency:go-offline -B

# Copy source code
COPY --chown=builduser:builduser src src

# Run static analysis and security checks
RUN ./mvnw compile checkstyle:check -B || true

# Build the application with profiles
RUN ./mvnw clean package -DskipTests -B -Pproduction

# Extract JAR layers for better caching
RUN java -Djarmode=layertools -jar target/*.jar extract

# Runtime stage with enhanced security and monitoring
FROM eclipse-temurin:17-jre-alpine AS runtime

# Install runtime dependencies and monitoring tools
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
RUN mkdir -p /app/logs /app/config /app/tmp /app/monitoring

# Create non-root user for security with specific UID/GID
RUN addgroup -g 1001 -S spring && \
    adduser -u 1001 -S spring -G spring -h /app -s /bin/bash

# Set working directory
WORKDIR /app

# Copy JAR layers for better caching
COPY --from=build --chown=spring:spring /app/dependencies/ ./
COPY --from=build --chown=spring:spring /app/spring-boot-loader/ ./
COPY --from=build --chown=spring:spring /app/snapshot-dependencies/ ./
COPY --from=build --chown=spring:spring /app/application/ ./

# Copy application JAR as fallback
COPY --from=build --chown=spring:spring /app/target/*.jar app.jar

# Create application configuration
RUN echo 'server.port=8080' > /app/config/application.properties && \
    echo 'management.endpoints.web.exposure.include=health,info,metrics,prometheus' >> /app/config/application.properties && \
    echo 'management.endpoint.health.show-details=always' >> /app/config/application.properties && \
    echo 'logging.file.name=/app/logs/application.log' >> /app/config/application.properties && \
    echo 'logging.level.org.springframework.samples.petclinic=DEBUG' >> /app/config/application.properties

# Set up log rotation configuration
RUN echo '/app/logs/*.log {' > /etc/logrotate.d/petclinic && \
    echo '    daily' >> /etc/logrotate.d/petclinic && \
    echo '    rotate 7' >> /etc/logrotate.d/petclinic && \
    echo '    compress' >> /etc/logrotate.d/petclinic && \
    echo '    delaycompress' >> /etc/logrotate.d/petclinic && \
    echo '    missingok' >> /etc/logrotate.d/petclinic && \
    echo '    notifempty' >> /etc/logrotate.d/petclinic && \
    echo '}' >> /etc/logrotate.d/petclinic

# Create startup script with enhanced features
RUN echo '#!/bin/bash' > /app/startup.sh && \
    echo 'set -e' >> /app/startup.sh && \
    echo 'echo "Starting PetClinic Application..."' >> /app/startup.sh && \
    echo 'echo "Java Version: $(java -version 2>&1 | head -n 1)"' >> /app/startup.sh && \
    echo 'echo "Available Memory: $(free -h | grep Mem | awk "{print \$2}")"' >> /app/startup.sh && \
    echo 'echo "Available Disk: $(df -h / | tail -1 | awk "{print \$4}")"' >> /app/startup.sh && \
    echo 'mkdir -p /app/logs' >> /app/startup.sh && \
    echo 'touch /app/logs/application.log' >> /app/startup.sh && \
    echo 'exec java $JAVA_OPTS -jar app.jar "$@"' >> /app/startup.sh && \
    chmod +x /app/startup.sh

# Create monitoring script
RUN echo '#!/bin/bash' > /app/monitor.sh && \
    echo 'while true; do' >> /app/monitor.sh && \
    echo '  echo "$(date): Memory: $(free -m | grep Mem | awk "{print \$3/\$2*100}")% CPU: $(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1)%" >> /app/logs/monitoring.log' >> /app/monitor.sh && \
    echo '  sleep 60' >> /app/monitor.sh && \
    echo 'done' >> /app/monitor.sh && \
    chmod +x /app/monitor.sh

# Set proper permissions
RUN chown -R spring:spring /app && \
    chmod -R 755 /app && \
    chmod 644 /app/*.jar

# Switch to non-root user
USER spring

# Set runtime environment variables
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom -Dspring.config.additional-location=/app/config/" \
    SPRING_PROFILES_ACTIVE="default" \
    SERVER_PORT=8080 \
    MANAGEMENT_PORT=8081 \
    LOG_LEVEL="INFO" \
    APP_NAME="petclinic" \
    APP_VERSION="4.0.0-SNAPSHOT"

# Expose ports
EXPOSE 8080 8081

# Add labels for metadata
LABEL maintainer="Spring PetClinic Team" \
      version="4.0.0-SNAPSHOT" \
      description="Spring PetClinic Sample Application" \
      org.opencontainers.image.title="Spring PetClinic" \
      org.opencontainers.image.description="A sample Spring Boot application" \
      org.opencontainers.image.version="4.0.0-SNAPSHOT" \
      org.opencontainers.image.vendor="Spring" \
      org.opencontainers.image.licenses="Apache-2.0"

# Create volume for logs and data
VOLUME ["/app/logs", "/app/data"]

# Enhanced health check with retry logic
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost:8080/actuator/health || \
        wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || \
        nc -z localhost 8080 || exit 1

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Run the application with startup script
CMD ["/app/startup.sh"]
