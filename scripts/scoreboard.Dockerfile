ARG VERSION

FROM eclipse-temurin:8-jdk AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends ant git \
    && rm -rf /var/lib/apt/lists/*
ARG VERSION
RUN git clone --depth 1 --branch ${VERSION} \
      https://github.com/rollerderby/scoreboard.git /src
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
