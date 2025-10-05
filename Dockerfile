# Build stage (optional if you build with Jenkins)
FROM eclipse-temurin:17-jre-alpine as runtime
WORKDIR /app

# Copy the fat jar built by Jenkins (mvn clean package -DskipTests)
COPY target/*.jar app.jar

# Tweak JVM for containers
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:InitialRAMPercentage=50 -XX:+UseG1GC -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]
