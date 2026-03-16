# -------------------------------
# Build stage
# -------------------------------
FROM eclipse-temurin:17-jdk-jammy AS build

WORKDIR /app

# Copy Maven wrapper & pom.xml first for caching
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .

RUN chmod +x ./mvnw

# Download dependencies (cached layer)
RUN ./mvnw dependency:go-offline -B

# Copy source
COPY src src

# Build application
RUN ./mvnw clean package -DskipTests -B


# -------------------------------
# Runtime stage
# -------------------------------
FROM eclipse-temurin:17-jre-jammy

# Create non-root user
RUN groupadd -g 1001 spring && \
    useradd -u 1001 -g spring spring

WORKDIR /app

# Copy JAR from build stage
COPY --from=build /app/target/*.jar app.jar

RUN chown spring:spring app.jar

USER spring

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java","-jar","app.jar"]
