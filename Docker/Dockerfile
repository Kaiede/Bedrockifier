
ARG swift_base=swift
ARG swift_version=5.6.2
ARG swift_image=$swift_base:$swift_version

###### BUILDER
FROM $swift_image as builder
WORKDIR /project

ADD . /project
RUN swift build -c release -Xswiftc -g

###### RUNTIME CONTAINER
FROM $swift_image-slim
WORKDIR /opt/bedrock

ARG arch

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/entrypoint-demoter", "--match", "/backups", "--debug", "--stdin-on-term", "stop", "/opt/bedrock/bedrockifierd"]
HEALTHCHECK --start-period=1m CMD bash /opt/bedrock/healthcheck.sh

ARG EASY_ADD_VERSION=0.7.0
ADD https://github.com/itzg/easy-add/releases/download/${EASY_ADD_VERSION}/easy-add_linux_${arch} /usr/local/bin/easy-add
RUN chmod +x /usr/local/bin/easy-add

RUN easy-add --var version=0.2.1 --var app=entrypoint-demoter --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${arch}.tar.gz

COPY --from=builder /project/.build/release/bedrockifier-tool .
COPY --from=builder /project/.build/release/bedrockifierd .
COPY ./Docker/healthcheck.sh .

