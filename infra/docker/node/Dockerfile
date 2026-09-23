FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache tini git bash docker-cli docker-cli-compose curl wget python3 apache2-utils coreutils

COPY runtime/entrypoint.sh /entrypoint.sh
COPY runtime/node-env-bridge.sh /node-env-bridge.sh
COPY runtime/load-dotenv.sh /load-dotenv.sh
COPY runtime/load-dotenv.js /load-dotenv.js
RUN chmod +x /entrypoint.sh /node-env-bridge.sh /load-dotenv.sh

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
