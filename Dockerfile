# -------- 1st stage : build --------
FROM maven:3.9-amazoncorretto-17-alpine AS builder

WORKDIR /app

COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src
RUN mvn -B clean package -DskipTests

# -------- 2nd stage : runtime --------
FROM amazoncorretto:17-alpine

WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
