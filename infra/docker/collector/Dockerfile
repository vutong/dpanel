FROM alpine:3.21

RUN apk add --no-cache bash docker-cli docker-cli-compose python3 coreutils curl

WORKDIR /opt/stack

# Script is bind-mounted from the stack volume at runtime.
CMD ["/bin/bash", "/opt/stack/infra/scripts/cache-collector-loop.sh"]
