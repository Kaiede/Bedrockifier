ARG swift_image=swift:6.0.3-jammy

###### BUILDER
FROM $swift_image as builder
WORKDIR /project

ADD . /project
RUN swift build -c release -Xswiftc -g

###### RUNTIME CONTAINER
FROM $swift_image-slim
WORKDIR /opt/bedrock

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG GITHUB_BASEURL=https://github.com

ARG EASY_ADD_VERSION=0.8.3
ADD ${GITHUB_BASEURL}/itzg/easy-add/releases/download/${EASY_ADD_VERSION}/easy-add_${TARGETOS}_${TARGETARCH}${TARGETVARIANT} /usr/bin/easy-add
RUN chmod +x /usr/bin/easy-add

ARG RCON_CLI_VERSION=1.6.4
RUN easy-add --var os=${TARGETOS} --var arch=${TARGETARCH}${TARGETVARIANT} \
  --var version=${RCON_CLI_VERSION} --var app=rcon-cli --file {{.app}} \
  --from ${GITHUB_BASEURL}/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_{{.os}}_{{.arch}}.tar.gz

ARG ENTRYPOINT_DEMOTER_VERSION=0.4.2
RUN easy-add --var version=${ENTRYPOINT_DEMOTER_VERSION} --var app=entrypoint-demoter --file {{.app}} --from ${GITHUB_BASEURL}/itzg/{{.app}}/releases/download/v{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz

COPY --from=builder /project/.build/release/bedrockifier-tool .
COPY --from=builder /project/.build/release/bedrockifierd .
COPY ./Docker/entry.sh .
COPY ./Docker/healthcheck.sh .
COPY ./Docker/trigger-backup.sh .

ENTRYPOINT [ "/opt/bedrock/entry.sh" ]
HEALTHCHECK --start-period=1m CMD bash /opt/bedrock/healthcheck.sh
