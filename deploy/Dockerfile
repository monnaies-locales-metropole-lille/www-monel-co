# www.monel.co — immutable SPIP image
#
# Everything SPIP executes lives in this image and is read-only at runtime.
# The three directories SPIP genuinely needs to write are volumes:
#
#   /var/www/spip/IMG     uploaded documents      (web-served, PHP execution denied)
#   /var/www/spip/local   generated CSS + images  (web-served, PHP execution denied)
#   /var/spip/tmp         cache, compiled skeletons, sessions, logs
#                         -> deliberately OUTSIDE the webroot via _DIR_TMP, so the
#                            compiled-skeleton directory is not reachable by URL at all.
#                            This is the path the 2026-08-21 payload executed from.
#
# Build:  docker build -f deploy/Dockerfile -t monel-spip:4.4.21-1 .
#         (build context is the repository root — the skeleton is the repo)

# ---------------------------------------------------------------------------
# Stage 1 — assemble the webroot
# ---------------------------------------------------------------------------
FROM composer:2 AS builder

RUN apk add --no-cache curl unzip

WORKDIR /build

# Pinned core. core.lock is the single source of truth for the version.
COPY deploy/core.lock /tmp/core.lock
RUN SPIP_VERSION="$(grep -E '^SPIP_VERSION=' /tmp/core.lock | cut -d= -f2)" \
    && echo "Installing SPIP ${SPIP_VERSION}" \
    && composer create-project \
        --no-dev --no-scripts --no-progress --prefer-dist \
        --repository='{"type":"composer","url":"https://get.spip.net/composer"}' \
        "spip/spip:${SPIP_VERSION}" /build

# Pinned contrib plugins, checksum-verified. Build fails on any mismatch.
COPY deploy/plugins.lock /tmp/plugins.lock
COPY deploy/bin/fetch-plugins.sh /tmp/fetch-plugins.sh
RUN chmod +x /tmp/fetch-plugins.sh \
    && /tmp/fetch-plugins.sh /tmp/plugins.lock /build/plugins

# The site templates. In the dev checkout this is a `squelettes -> ..` symlink;
# here it is a real directory so the image is self-contained. spip/, incidents/ and
# compromised-backup/ never enter the build context (see deploy/.dockerignore);
# deploy/ does, because the COPYs above and below need it, so it is pruned below.
COPY . /build/squelettes/

# Strip everything that must never be reachable in production:
#   spip_loader.php / ecrire/install  remote-code paths by design
#   fichiers_obsoletes_*              accumulated upstream cruft, as seen in the
#                                     old install (three directories of it)
#   composer.*, phpcs.xml.dist, .git  build metadata, not web content
#   squelettes/deploy                 this tooling; it is in the context only
#                                     because the COPY steps above need it
#   tmp, local, IMG                   volumes at runtime; bake nothing into them
#
# Comments are kept out of the RUN body on purpose: Docker strips whole-line
# comments during line-continuation, and a stray one that survives would comment
# out the remainder of the joined command.
RUN set -eux; \
    rm -f  /build/spip_loader.php /build/spip_loader_list.json; \
    rm -rf /build/ecrire/install; \
    rm -rf /build/fichiers_obsoletes_*; \
    rm -f  /build/composer.json /build/composer.lock /build/phpcs.xml.dist; \
    rm -rf /build/.git /build/squelettes/.git; \
    rm -rf /build/squelettes/deploy; \
    rm -rf /build/tmp /build/local /build/IMG; \
    mkdir -p /build/IMG /build/local

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
FROM php:8.4-fpm-alpine AS runtime

# gd: SPIP image filters (avoids ever shelling out to ImageMagick)
# intl/zip/mysqli/pdo_mysql: SPIP core + MariaDB
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS icu-dev libzip-dev libpng-dev libjpeg-turbo-dev freetype-dev \
    && apk add --no-cache icu-libs libzip libpng libjpeg-turbo freetype \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd intl zip mysqli pdo_mysql opcache \
    && apk del .build-deps

# Remove the download tools. The 2026-08-21 intrusion fetched hasil.php with
# `wget`, so this is worth doing — but be clear about how far it goes: Alpine's
# /usr/bin/wget is a busybox applet, and dropping the symlink does not remove the
# applet itself (`busybox wget` still resolves). This raises the bar; it is not a
# boundary. The controls that actually stop a second stage are disable_functions
# (no exec family, so PHP cannot spawn any of this) and egress filtering at the
# host firewall — see README §Egress. Do not install curl "for debugging".
RUN rm -f /usr/bin/wget /usr/bin/curl /usr/bin/ftpget /usr/bin/nc /usr/bin/telnet

ARG UID=65532
ARG GID=65532
RUN addgroup -g "$GID" spip && adduser -u "$UID" -G spip -s /sbin/nologin -D spip

COPY --from=builder --chown=root:root /build /var/www/spip

# The webroot is root-owned and mode 0555/0444 throughout, so PHP cannot write a
# shell into it even without `read_only: true` on the container. Two exceptions,
# handed to the runtime user because SPIP genuinely writes there: IMG and local.
# /var/spip/tmp is the third, deliberately outside the webroot.
# (Comments stay outside the RUN body — see the note in stage 1.)
RUN set -eux; \
    find /var/www/spip -type d -exec chmod 0555 {} +; \
    find /var/www/spip -type f -exec chmod 0444 {} +; \
    chown "$UID:$GID" /var/www/spip/IMG /var/www/spip/local; \
    chmod 0750 /var/www/spip/IMG /var/www/spip/local; \
    mkdir -p /var/spip/tmp /var/spip/secrets; \
    chown "$UID:$GID" /var/spip/tmp; \
    chmod 0750 /var/spip/tmp; \
    chmod 0555 /var/spip/secrets

COPY deploy/php/zz-spip-hardening.ini  /usr/local/etc/php/conf.d/zz-spip-hardening.ini
COPY deploy/php/opcache-blacklist.txt  /usr/local/etc/php/opcache-blacklist.txt
COPY deploy/php/www.conf               /usr/local/etc/php-fpm.d/zz-www.conf
COPY deploy/config/mes_options.php     /var/www/spip/config/mes_options.php

RUN chmod 0444 /var/www/spip/config/mes_options.php \
                /usr/local/etc/php/conf.d/zz-spip-hardening.ini \
                /usr/local/etc/php/opcache-blacklist.txt \
                /usr/local/etc/php-fpm.d/zz-www.conf

USER spip
WORKDIR /var/www/spip

VOLUME ["/var/www/spip/IMG", "/var/www/spip/local", "/var/spip/tmp"]

EXPOSE 9000

# Fails if PHP cannot start or an extension is missing — catches a broken
# rebuild before it takes traffic.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php -r 'exit(extension_loaded("gd") && extension_loaded("mysqli") ? 0 : 1);'

CMD ["php-fpm", "-F"]
