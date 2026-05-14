ARG swift_image=swift:6.3.1

###### BUILDER
FROM $swift_image AS builder
WORKDIR /project

ADD . /project
RUN swift build -c release

###### DEPENDENCY FETCHER
FROM $swift_image-slim AS deps

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
ARG GITHUB_BASEURL=https://github.com

# renovate: datasource=github-releases packageName=itzg/easy-add
ARG EASY_ADD_VERSION=0.8.12
ADD ${GITHUB_BASEURL}/itzg/easy-add/releases/download/${EASY_ADD_VERSION}/easy-add_${TARGETOS}_${TARGETARCH}${TARGETVARIANT} /usr/bin/easy-add
RUN chmod +x /usr/bin/easy-add

# renovate: datasource=github-releases packageName=itzg/entrypoint-demoter
ARG ENTRYPOINT_DEMOTER_VERSION=0.4.10
RUN easy-add --var version=${ENTRYPOINT_DEMOTER_VERSION} --var app=entrypoint-demoter --file {{.app}} --from ${GITHUB_BASEURL}/itzg/{{.app}}/releases/download/v{{.version}}/{{.app}}_{{.version}}_linux_${TARGETARCH}.tar.gz

###### RUNTIME CONTAINER
FROM $swift_image-slim
WORKDIR /opt/bedrock

ARG IMAGEVARIANT

RUN --mount=source=Docker/install-dependencies.sh,target=/tmp/install-dependencies.sh \
    /tmp/install-dependencies.sh ${IMAGEVARIANT}

COPY --from=deps /usr/local/bin/entrypoint-demoter /usr/local/bin/
COPY --from=builder /project/.build/release/bedrockifier-tool /project/.build/release/bedrockifierd .
RUN ln -s bedrockifier bedrockifierd && ln -s bedrockfier bedrockifier-tool
COPY ./Docker/entry.sh ./Docker/trigger-backup.sh .

ENTRYPOINT [ "/opt/bedrock/entry.sh" ]
HEALTHCHECK --start-period=1m CMD curl -f http://localhost:8080/health
