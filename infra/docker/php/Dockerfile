FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    libzip-dev icu-dev oniguruma-dev freetype-dev libjpeg-turbo-dev libpng-dev git \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) pdo_mysql mysqli zip intl opcache gd bcmath \
  && rm -rf /var/cache/apk/*

COPY config/99-custom.ini /usr/local/etc/php/conf.d/99-custom.ini
WORKDIR /var/www
EXPOSE 9000
