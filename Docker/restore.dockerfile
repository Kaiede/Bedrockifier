FROM alpine:3.20

RUN apk add --no-cache \
      bash \
      coreutils \
      dialog \
      findutils \
      tzdata \
      unzip

COPY ./Docker/restore-menu.sh /usr/local/bin/restore-menu.sh
RUN chmod +x /usr/local/bin/restore-menu.sh

ENTRYPOINT ["/usr/local/bin/restore-menu.sh"]
