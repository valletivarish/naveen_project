# Use lightweight Java runtime image
FROM eclipse-temurin:17-jre

# Set working directory inside container
WORKDIR /app

# Copy the built jar file from target folder to container
COPY target/*.jar app.jar

# Command to run the app
ENTRYPOINT ["java","-jar","app.jar"]
