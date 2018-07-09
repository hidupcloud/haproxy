FROM haproxy:1.5-alpine
LABEL maintenance="Juan Bautista Mesa Roldán <juan.mesa@hidup.io>"

RUN apk update
RUN apk add jq
RUN rm -rf /var/cache/apk/*

ADD deploy/haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

ADD deploy/docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
