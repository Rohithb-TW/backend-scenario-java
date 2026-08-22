FROM eclipse-temurin:21-jre

ARG JAR_FILE=target/spring-petclinic-rest-4.0.2.jar

WORKDIR /app
COPY ${JAR_FILE} app.jar

EXPOSE 9966

ENTRYPOINT ["java", "-jar", "/app/app.jar"]