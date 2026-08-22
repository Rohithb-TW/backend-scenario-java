# ── Stage 1: Build ───────────────────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Copy Maven wrapper and pom first (layer cache for dependencies)
COPY mvnw pom.xml ./
COPY .mvn .mvn

# Download dependencies without building (cached unless pom.xml changes)
RUN ./mvnw dependency:go-offline -q

# Copy source and build
COPY src ./src
RUN ./mvnw clean package -DskipTests -q

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime

# Security: run as non-root user
RUN addgroup -S petclinic && adduser -S petclinic -G petclinic
WORKDIR /app

# Copy only the fat JAR from builder
COPY --from=builder /app/target/spring-petclinic-rest-*.jar app.jar

# Switch to non-root
USER petclinic

# Expose app port
EXPOSE 9966

# Health check — used by Kubernetes liveness/readiness probes
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:9966/petclinic/actuator/health || exit 1

ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
