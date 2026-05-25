FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache tini git bash docker-cli curl wget

COPY runtime/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
