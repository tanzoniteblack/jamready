ARG SCOREBOARD_REPOSITORY=https://github.com/rollerderby/scoreboard.git
ARG VERSION

FROM eclipse-temurin:8-jdk AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends ant git \
    && rm -rf /var/lib/apt/lists/*
ARG VERSION
ARG SCOREBOARD_REPOSITORY
RUN git clone --depth 1 --branch ${VERSION} ${SCOREBOARD_REPOSITORY} /src
WORKDIR /src
RUN ant compile

FROM eclipse-temurin:8-jre AS runner
WORKDIR /scoreboard
COPY --from=builder /src .
EXPOSE 8000
ENTRYPOINT ["java", \
  "-Done-jar.silent=true", \
  "-Dorg.eclipse.jetty.server.LEVEL=WARN", \
  "-jar", "lib/crg-scoreboard.jar"]
