# Multi-stage build for Spring Pet Clinic Application
FROM eclipse-temurin:17-jdk-alpine AS build

# Install build dependencies
RUN apk add --no-cache \
    curl \
    wget \
    git \
    bash \
    tar \
    gzip \
    ca-certificates

# Set build environment variables
ENV MAVEN_OPTS="-Xmx1024m" \
    JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom"

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

# Copy source code
COPY src ./src

# Build the application
RUN ./mvnw clean package -DskipTests -B

# Runtime stage
FROM eclipse-temurin:17-jre-alpine AS runtime

# Install runtime dependencies and utilities
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
    htop \
    vim \
    nano && \
    rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Create application directories
RUN mkdir -p /app/logs /app/config /app/data /app/scripts /app/backup

# Create non-root user for security
RUN addgroup -g 1001 -S spring && \
    adduser -u 1001 -S spring -G spring -h /app -s /bin/bash

# Set working directory
WORKDIR /app

# Copy the built JAR from build stage
COPY --from=build --chown=spring:spring /app/target/*.jar app.jar

# Create application configuration files
RUN echo 'server.port=8080' > /app/config/application.properties && \
    echo 'management.endpoints.web.exposure.include=health,info,metrics,prometheus' >> /app/config/application.properties && \
    echo 'management.endpoint.health.show-details=always' >> /app/config/application.properties && \
    echo 'logging.file.name=/app/logs/application.log' >> /app/config/application.properties && \
    echo 'logging.level.org.springframework.samples.petclinic=INFO' >> /app/config/application.properties && \
    echo 'spring.jpa.show-sql=false' >> /app/config/application.properties && \
    echo 'spring.datasource.hikari.maximum-pool-size=10' >> /app/config/application.properties

# Create database-specific configurations
RUN echo 'spring.datasource.url=jdbc:mysql://mysql:3306/petclinic' > /app/config/application-mysql.properties && \
    echo 'spring.datasource.username=petclinic' >> /app/config/application-mysql.properties && \
    echo 'spring.datasource.password=petclinic' >> /app/config/application-mysql.properties && \
    echo 'spring.jpa.database-platform=org.hibernate.dialect.MySQL8Dialect' >> /app/config/application-mysql.properties

RUN echo 'spring.datasource.url=jdbc:postgresql://postgres:5432/petclinic' > /app/config/application-postgres.properties && \
    echo 'spring.datasource.username=petclinic' >> /app/config/application-postgres.properties && \
    echo 'spring.datasource.password=petclinic' >> /app/config/application-postgres.properties && \
    echo 'spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect' >> /app/config/application-postgres.properties

# Create startup script
RUN echo '#!/bin/bash' > /app/scripts/startup.sh && \
    echo 'set -e' >> /app/scripts/startup.sh && \
    echo 'echo "Starting PetClinic Application..."' >> /app/scripts/startup.sh && \
    echo 'echo "Date: $(date)"' >> /app/scripts/startup.sh && \
    echo 'echo "Java Version: $(java -version 2>&1 | head -n 1)"' >> /app/scripts/startup.sh && \
    echo 'echo "Available Memory: $(free -h | grep Mem | awk "{print \$2}")"' >> /app/scripts/startup.sh && \
    echo 'echo "Available Disk: $(df -h / | tail -1 | awk "{print \$4}")"' >> /app/scripts/startup.sh && \
    echo 'mkdir -p /app/logs' >> /app/scripts/startup.sh && \
    echo 'touch /app/logs/application.log' >> /app/scripts/startup.sh && \
    echo 'exec java $JAVA_OPTS -jar app.jar "$@"' >> /app/scripts/startup.sh && \
    chmod +x /app/scripts/startup.sh

# Create monitoring script
RUN echo '#!/bin/bash' > /app/scripts/monitor.sh && \
    echo 'while true; do' >> /app/scripts/monitor.sh && \
    echo '  echo "$(date): Memory: $(free -m | grep Mem | awk "{print \$3/\$2*100}")% CPU: $(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1)%" >> /app/logs/monitoring.log' >> /app/scripts/monitor.sh && \
    echo '  sleep 60' >> /app/scripts/monitor.sh && \
    echo 'done' >> /app/scripts/monitor.sh && \
    chmod +x /app/scripts/monitor.sh

# Create health check script
RUN echo '#!/bin/bash' > /app/scripts/healthcheck.sh && \
    echo 'curl -f http://localhost:8080/actuator/health || wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || nc -z localhost 8080' >> /app/scripts/healthcheck.sh && \
    chmod +x /app/scripts/healthcheck.sh

# Create backup script
RUN echo '#!/bin/bash' > /app/scripts/backup.sh && \
    echo 'BACKUP_DIR="/app/backup"' >> /app/scripts/backup.sh && \
    echo 'TIMESTAMP=$(date +"%Y%m%d_%H%M%S")' >> /app/scripts/backup.sh && \
    echo 'mkdir -p $BACKUP_DIR' >> /app/scripts/backup.sh && \
    echo 'tar -czf $BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz /app/logs/' >> /app/scripts/backup.sh && \
    echo 'echo "Backup completed: $TIMESTAMP"' >> /app/scripts/backup.sh && \
    chmod +x /app/scripts/backup.sh

# Set proper permissions
RUN chown -R spring:spring /app && \
    chmod -R 755 /app/scripts && \
    chmod 644 /app/app.jar

# Switch to non-root user
USER spring

# Set runtime environment variables
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom -Dspring.config.additional-location=/app/config/" \
    SPRING_PROFILES_ACTIVE="default" \
    SERVER_PORT=8080 \
    MANAGEMENT_PORT=8081 \
    LOG_LEVEL="INFO" \
    APP_NAME="petclinic" \
    APP_VERSION="4.0.0-SNAPSHOT" \
    SPRING_OUTPUT_ANSI_ENABLED="ALWAYS" \
    LOGGING_FILE_NAME="/app/logs/application.log"

# Expose ports
EXPOSE 8080 8081

# Add metadata labels
LABEL maintainer="Spring PetClinic Team" \
      version="4.0.0-SNAPSHOT" \
      description="Spring PetClinic Sample Application" \
      org.opencontainers.image.title="Spring PetClinic" \
      org.opencontainers.image.description="A sample Spring Boot application" \
      org.opencontainers.image.version="4.0.0-SNAPSHOT" \
      org.opencontainers.image.vendor="Spring" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.url="https://github.com/spring-projects/spring-petclinic" \
      application.framework="Spring Boot" \
      application.language="Java" \
      deployment.environment="production"

# Create volumes for persistent data
VOLUME ["/app/logs", "/app/data", "/app/backup"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /app/scripts/healthcheck.sh

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Run the application
CMD ["/app/scripts/startup.sh"] >> /app/scripts/backup.sh && \
    echo 'TIMESTAMP=$(date +"%Y%m%d_%H%M%S")' >> /app/scripts/backup.sh && \
    echo 'mkdir -p $BACKUP_DIR' >> /app/scripts/backup.sh && \
    echo 'tar -czf $BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz /app/logs/' >> /app/scripts/backup.sh && \
    echo 'echo "Backup completed: $TIMESTAMP"' >> /app/scripts/backup.sh && \
    chmod +x /app/scripts/backup.sh

# Set proper permissions
RUN chown -R spring:spring /app && \
    chmod -R 755 /app/scripts && \
    chmod 644 /app/app.jar
>>>>>>> 3c190f4 (Docker layer caching demo setup)

# Switch to non-root user
USER spring

# Set runtime environment variables
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom -Dspring.config.additional-location=/app/config/" \
    SPRING_PROFILES_ACTIVE="default" \
    SERVER_PORT=8080 \
    MANAGEMENT_PORT=8081 \
    LOG_LEVEL="INFO" \
    APP_NAME="petclinic" \
<<<<<<< HEAD
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
=======
    APP_VERSION="4.0.0-SNAPSHOT" \
    SPRING_OUTPUT_ANSI_ENABLED="ALWAYS" \
    LOGGING_FILE_NAME="/app/logs/application.log"

# Expose ports
EXPOSE 8080 8081

# Add metadata labels
LABEL maintainer="Spring PetClinic Team" \
      version="4.0.0-SNAPSHOT" \
      description="Spring PetClinic Sample Application" \
      org.opencontainers.image.title="Spring PetClinic" \
      org.opencontainers.image.description="A sample Spring Boot application" \
      org.opencontainers.image.version="4.0.0-SNAPSHOT" \
      org.opencontainers.image.vendor="Spring" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.url="https://github.com/spring-projects/spring-petclinic" \
      application.framework="Spring Boot" \
      application.language="Java" \
      deployment.environment="production"

# Create volumes for persistent data
VOLUME ["/app/logs", "/app/data", "/app/backup"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /app/scripts/healthcheck.sh

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Run the application
CMD ["/app/scripts/startup.sh"] | awk "{print \$4}")"' >> /app/scripts/startup.sh && \
    echo 'echo "CPU Information: $(nproc) cores"' >> /app/scripts/startup.sh && \
    echo 'echo "Network Interfaces:"' >> /app/scripts/startup.sh && \
    echo 'ip addr show | grep inet | head -5' >> /app/scripts/startup.sh && \
    echo 'echo "========================================"' >> /app/scripts/startup.sh && \
    echo '' >> /app/scripts/startup.sh && \
    echo '# Create necessary directories' >> /app/scripts/startup.sh && \
    echo 'mkdir -p /app/logs /app/data /app/tmp /app/backup' >> /app/scripts/startup.sh && \
    echo 'touch /app/logs/petclinic.log' >> /app/scripts/startup.sh && \
    echo 'touch /app/logs/access.log' >> /app/scripts/startup.sh && \
    echo 'touch /app/logs/error.log' >> /app/scripts/startup.sh && \
    echo '' >> /app/scripts/startup.sh && \
    echo '# Set JVM options based on available memory' >> /app/scripts/startup.sh && \
    echo 'TOTAL_MEM=$(free -m | grep Mem | awk "{print \$2}")' >> /app/scripts/startup.sh && \
    echo 'if [ $TOTAL_MEM -gt 4096 ]; then' >> /app/scripts/startup.sh && \
    echo '    export JAVA_OPTS="$JAVA_OPTS -Xms1g -Xmx2g"' >> /app/scripts/startup.sh && \
    echo 'elif [ $TOTAL_MEM -gt 2048 ]; then' >> /app/scripts/startup.sh && \
    echo '    export JAVA_OPTS="$JAVA_OPTS -Xms512m -Xmx1g"' >> /app/scripts/startup.sh && \
    echo 'else' >> /app/scripts/startup.sh && \
    echo '    export JAVA_OPTS="$JAVA_OPTS -Xms256m -Xmx512m"' >> /app/scripts/startup.sh && \
    echo 'fi' >> /app/scripts/startup.sh && \
    echo '' >> /app/scripts/startup.sh && \
    echo 'echo "Starting application with JVM options: $JAVA_OPTS"' >> /app/scripts/startup.sh && \
    echo 'echo "Active Spring profiles: $SPRING_PROFILES_ACTIVE"' >> /app/scripts/startup.sh && \
    echo '' >> /app/scripts/startup.sh && \
    echo '# Start the application' >> /app/scripts/startup.sh && \
    echo 'exec java $JAVA_OPTS -jar /app/app.jar "$@"' >> /app/scripts/startup.sh && \
    chmod +x /app/scripts/startup.sh

# Create monitoring and health check scripts
RUN echo '#!/bin/bash' > /app/scripts/monitor.sh && \
    echo 'LOG_FILE="/app/logs/monitoring.log"' >> /app/scripts/monitor.sh && \
    echo 'while true; do' >> /app/scripts/monitor.sh && \
    echo '    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")' >> /app/scripts/monitor.sh && \
    echo '    MEMORY_USAGE=$(free | grep Mem | awk "{printf \"%.2f\", \$3/\$2 * 100.0}")' >> /app/scripts/monitor.sh && \
    echo '    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1)' >> /app/scripts/monitor.sh && \
    echo '    DISK_USAGE=$(df -h / | tail -1 | awk "{print \$5}" | cut -d"%" -f1)' >> /app/scripts/monitor.sh && \
    echo '    LOAD_AVG=$(uptime | awk -F"load average:" "{print \$2}")' >> /app/scripts/monitor.sh && \
    echo '    echo "$TIMESTAMP - Memory: ${MEMORY_USAGE}% CPU: ${CPU_USAGE}% Disk: ${DISK_USAGE}% Load:$LOAD_AVG" >> $LOG_FILE' >> /app/scripts/monitor.sh && \
    echo '    sleep 60' >> /app/scripts/monitor.sh && \
    echo 'done' >> /app/scripts/monitor.sh && \
    chmod +x /app/scripts/monitor.sh

RUN echo '#!/bin/bash' > /app/scripts/healthcheck.sh && \
    echo 'HEALTH_URL="http://localhost:8080/petclinic/actuator/health"' >> /app/scripts/healthcheck.sh && \
    echo 'MAX_RETRIES=3' >> /app/scripts/healthcheck.sh && \
    echo 'RETRY_COUNT=0' >> /app/scripts/healthcheck.sh && \
    echo '' >> /app/scripts/healthcheck.sh && \
    echo 'while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do' >> /app/scripts/healthcheck.sh && \
    echo '    if curl -f -s $HEALTH_URL > /dev/null 2>&1; then' >> /app/scripts/healthcheck.sh && \
    echo '        echo "Health check passed"' >> /app/scripts/healthcheck.sh && \
    echo '        exit 0' >> /app/scripts/healthcheck.sh && \
    echo '    elif wget --quiet --tries=1 --spider $HEALTH_URL > /dev/null 2>&1; then' >> /app/scripts/healthcheck.sh && \
    echo '        echo "Health check passed (wget)"' >> /app/scripts/healthcheck.sh && \
    echo '        exit 0' >> /app/scripts/healthcheck.sh && \
    echo '    elif nc -z localhost 8080 > /dev/null 2>&1; then' >> /app/scripts/healthcheck.sh && \
    echo '        echo "Port check passed"' >> /app/scripts/healthcheck.sh && \
    echo '        exit 0' >> /app/scripts/healthcheck.sh && \
    echo '    fi' >> /app/scripts/healthcheck.sh && \
    echo '    RETRY_COUNT=$((RETRY_COUNT + 1))' >> /app/scripts/healthcheck.sh && \
    echo '    echo "Health check attempt $RETRY_COUNT failed, retrying..."' >> /app/scripts/healthcheck.sh && \
    echo '    sleep 2' >> /app/scripts/healthcheck.sh && \
    echo 'done' >> /app/scripts/healthcheck.sh && \
    echo '' >> /app/scripts/healthcheck.sh && \
    echo 'echo "All health check attempts failed"' >> /app/scripts/healthcheck.sh && \
    echo 'exit 1' >> /app/scripts/healthcheck.sh && \
    chmod +x /app/scripts/healthcheck.sh

# Create backup and maintenance scripts
RUN echo '#!/bin/bash' > /app/scripts/backup.sh && \
    echo 'BACKUP_DIR="/app/backup"' >> /app/scripts/backup.sh && \
    echo 'TIMESTAMP=$(date +"%Y%m%d_%H%M%S")' >> /app/scripts/backup.sh && \
    echo 'mkdir -p $BACKUP_DIR' >> /app/scripts/backup.sh && \
    echo 'tar -czf $BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz /app/logs/' >> /app/scripts/backup.sh && \
    echo 'tar -czf $BACKUP_DIR/config_backup_$TIMESTAMP.tar.gz /app/config/' >> /app/scripts/backup.sh && \
    echo 'find $BACKUP_DIR -name "*backup*.tar.gz" -mtime +7 -delete' >> /app/scripts/backup.sh && \
    echo 'echo "Backup completed: $TIMESTAMP"' >> /app/scripts/backup.sh && \
    chmod +x /app/scripts/backup.sh

# Set comprehensive file permissions
RUN chown -R spring:spring /app && \
    chmod -R 755 /app/scripts && \
    chmod -R 644 /app/config && \
    chmod -R 755 /app/logs && \
    chmod -R 755 /app/data && \
    chmod 644 /app/app.jar

# Switch to non-root user
USER spring

# Set comprehensive runtime environment variables
ENV JAVA_OPTS="-server -XX:+UseG1GC -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+OptimizeStringConcat -XX:+UseStringDeduplication -Djava.security.egd=file:/dev/./urandom -Dspring.config.additional-location=/app/config/ -Dfile.encoding=UTF-8 -Duser.timezone=UTC" \
    SPRING_PROFILES_ACTIVE="default" \
    SERVER_PORT=8080 \
    MANAGEMENT_SERVER_PORT=8081 \
    LOG_LEVEL="INFO" \
    APP_NAME="petclinic" \
    APP_VERSION="4.0.0-SNAPSHOT" \
    SPRING_OUTPUT_ANSI_ENABLED="ALWAYS" \
    SPRING_BANNER_MODE="console" \
    SPRING_JPA_SHOW_SQL="false" \
    SPRING_JPA_HIBERNATE_DDL_AUTO="validate" \
    SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE="20" \
    SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE="5" \
    SPRING_CACHE_TYPE="caffeine" \
    MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE="health,info,metrics,prometheus,env,configprops" \
    MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS="always" \
    LOGGING_FILE_NAME="/app/logs/petclinic.log" \
    LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SAMPLES_PETCLINIC="INFO"

# Expose multiple ports for different services
EXPOSE 8080 8081 9090

# Add comprehensive metadata labels
LABEL maintainer="Spring PetClinic Development Team <petclinic@spring.io>" \
      version="4.0.0-SNAPSHOT" \
      description="Spring PetClinic Sample Application - A comprehensive veterinary clinic management system" \
      org.opencontainers.image.title="Spring PetClinic" \
      org.opencontainers.image.description="A sample Spring Boot application demonstrating various Spring technologies" \
      org.opencontainers.image.version="4.0.0-SNAPSHOT" \
      org.opencontainers.image.vendor="Spring Framework" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.url="https://github.com/spring-projects/spring-petclinic" \
      org.opencontainers.image.documentation="https://spring-petclinic.github.io/" \
      org.opencontainers.image.source="https://github.com/spring-projects/spring-petclinic" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date="2024-01-01T00:00:00Z" \
      org.label-schema.name="spring-petclinic" \
      org.label-schema.description="Spring PetClinic Application" \
      org.label-schema.url="https://spring.io/guides/gs/spring-boot/" \
      org.label-schema.vcs-url="https://github.com/spring-projects/spring-petclinic" \
      org.label-schema.vendor="Spring" \
      org.label-schema.version="4.0.0-SNAPSHOT" \
      application.framework="Spring Boot" \
      application.language="Java" \
      application.type="Web Application" \
      deployment.environment="production"

# Create volumes for persistent data
VOLUME ["/app/logs", "/app/data", "/app/backup", "/app/config"]

# Enhanced health check with comprehensive monitoring
HEALTHCHECK --interval=30s --timeout=15s --start-period=180s --retries=5 \
    CMD /app/scripts/healthcheck.sh

# Use dumb-init for proper signal handling and process management
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Default command to run the application
CMD ["/app/scripts/startup.sh"]
>>>>>>> 3c190f4 (Docker layer caching demo setup)
