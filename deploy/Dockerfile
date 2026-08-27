# www.monel.co — immutable SPIP image
#
# Apache + mod_php in a single container. Everything SPIP executes is baked in and
# read-only at runtime. The three directories SPIP genuinely needs to write are
# volumes:
#
#   /var/www/spip/IMG     uploaded documents      (served inert, PHP engine off)
#   /var/www/spip/local   generated CSS + images  (served, PHP engine off)
#   /var/spip/tmp         cache, compiled skeletons, sessions, logs
#                         -> deliberately OUTSIDE the webroot via _DIR_TMP, so the
#                            compiled-skeleton directory is not reachable by URL at
#                            all. This is the path the 2026-08-21 payload executed
#                            from.
#
# Build:  docker build -f deploy/Dockerfile -t monel-spip:3.8 .
#         (build context is the repository root — the skeleton is the repo)

# ---------------------------------------------------------------------------
# Stage 1 — assemble the webroot
# ---------------------------------------------------------------------------
FROM alpine:3.20 AS builder

RUN apk add --no-cache curl unzip

WORKDIR /build

# Pinned core, checksum-verified. core.lock is the single source of truth.
#
# The official zip rather than composer, because composer's spip/spip package does
# not install plugins-dist — see the note in core.lock. This is the composition
# upstream ships: core, the twenty bundled plugins, and vendor/.
COPY deploy/core.lock /tmp/core.lock
RUN set -eux; \
    . /tmp/core.lock; \
    echo "Installing SPIP ${SPIP_VERSION} from ${SPIP_URL}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/spip.zip "${SPIP_URL}"; \
    actual_size="$(wc -c < /tmp/spip.zip)"; \
    [ "$actual_size" = "${SPIP_SIZE}" ] || { echo "FATAL: size mismatch: expected ${SPIP_SIZE}, got $actual_size" >&2; exit 1; }; \
    echo "${SPIP_SHA256}  /tmp/spip.zip" | sha256sum -c - || { echo "FATAL: SPIP archive checksum mismatch — do not bypass" >&2; exit 1; }; \
    unzip -q /tmp/spip.zip -d /build; \
    rm -f /tmp/spip.zip; \
    test -d /build/plugins-dist/urls_etendues || { echo "FATAL: plugins-dist missing from the archive" >&2; exit 1; }

# Pinned contrib plugins, checksum-verified. Build fails on any mismatch.
COPY deploy/plugins.lock /tmp/plugins.lock
COPY deploy/bin/fetch-plugins.sh /tmp/fetch-plugins.sh
RUN chmod +x /tmp/fetch-plugins.sh \
    && /tmp/fetch-plugins.sh /tmp/plugins.lock /build/plugins

# The site templates. In the dev checkout this is a `squelettes -> ..` symlink;
# here it is a real directory so the image is self-contained. spip/, incidents/ and
# compromised-backup/ never enter the build context (see .dockerignore at the repo
# root); deploy/ does, because the COPYs need it, so it is pruned below.
COPY . /build/squelettes/

# Strip everything that must never be reachable in production:
#   spip_loader.php / ecrire/install  remote-code paths by design
#   fichiers_obsoletes_*              accumulated upstream cruft
#   composer.*, phpcs.xml.dist, .git  build metadata, not web content
#   squelettes/deploy                 this tooling
#   tmp, local, IMG                   volumes at runtime; bake nothing into them
#
# Then activate SPIP's own Apache rules: upstream ships them as htaccess.txt and
# the installer renames it. Doing it here means the deny rules for local/ and IMG/,
# the dotfile 404 and the IMG sandbox CSP come from the vendor and track SPIP
# releases, rather than being hand-ported and maintained by us.
#
# Comments are kept out of the RUN body on purpose: Docker strips whole-line
# comments during line-continuation, and a stray one that survived would comment
# out the remainder of the joined command.
RUN set -eux; \
    rm -f  /build/spip_loader.php /build/spip_loader_list.json; \
    rm -rf /build/ecrire/install; \
    rm -rf /build/fichiers_obsoletes_*; \
    rm -f  /build/composer.json /build/composer.lock /build/phpcs.xml.dist; \
    rm -rf /build/.git /build/squelettes/.git; \
    rm -rf /build/squelettes/deploy; \
    rm -rf /build/tmp /build/local /build/IMG; \
    mkdir -p /build/IMG /build/local; \
    cp /build/htaccess.txt /build/.htaccess; \
    find /build -type d -exec chmod 0555 {} +; \
    find /build -type f -exec chmod 0444 {} +; \
    chown -R 65532:65532 /build/IMG /build/local; \
    chmod 0750 /build/IMG /build/local

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
FROM php:8.4-apache AS runtime

# gd: SPIP image filters (avoids ever shelling out to ImageMagick)
# intl/zip/mysqli/pdo_mysql: SPIP core + MariaDB
#
# The apt-mark dance is the pattern the official php images use, and it is here
# for a reason: a plain `apt-get purge --auto-remove` of the -dev packages also
# removes the runtime shared objects they depend on (libpng16, libicu, libzip),
# and the extensions then fail to load at startup with the container still
# reporting healthy. Marking the libraries the built extensions actually link
# against as manually-installed keeps them and drops everything else.
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd intl zip mysqli pdo_mysql opcache; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark > /dev/null; \
    find /usr/local/lib/php/extensions -name '*.so' -exec ldd '{}' ';' \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) next; gsub("^/(usr/)?", "", so); printf "*/%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search 2>/dev/null \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# Remove the download tools. The 2026-08-21 intrusion fetched hasil.php with
# `wget`. Worth doing, but be clear how far it goes: this raises the bar, it is
# not a boundary. The controls that actually stop a second stage are
# disable_functions (no exec family, so PHP cannot spawn any of this) and egress
# filtering at the host firewall — see README §Egress. Do not reinstall curl
# "for debugging".
RUN rm -f /usr/bin/wget /usr/bin/curl /usr/bin/nc /usr/bin/telnet

# rewrite: SPIP's URL routing.  headers: the CSP sandbox on IMG/ and HSTS-adjacent
# headers.  Nothing else is enabled — notably not cgi, cgid or include.
RUN a2enmod rewrite headers remoteip && a2dismod -f autoindex status

ARG UID=65532
ARG GID=65532
RUN groupadd -g "$GID" spip && useradd -u "$UID" -g spip -s /usr/sbin/nologin -M spip

# Modes and ownership are already set in stage 1 — doing it there rather than with
# a RUN here matters: chmod'ing 57 MB of webroot in this stage would rewrite every
# file into a second layer, roughly doubling the image's contribution.
COPY --from=builder /build /var/www/spip

# Only the mountpoints outside the webroot are left to create; these are empty, so
# this layer stays small.
RUN set -eux; \
    mkdir -p /var/spip/tmp /var/spip/secrets; \
    chown "$UID:$GID" /var/spip/tmp; \
    chmod 0750 /var/spip/tmp; \
    chmod 0555 /var/spip/secrets

COPY deploy/php/zz-spip-hardening.ini  /usr/local/etc/php/conf.d/zz-spip-hardening.ini
COPY deploy/php/opcache-blacklist.txt  /usr/local/etc/php/opcache-blacklist.txt
COPY deploy/apache/monel.conf          /etc/apache2/sites-available/000-default.conf
COPY deploy/apache/hardening.conf      /etc/apache2/conf-available/zz-hardening.conf
COPY deploy/config/mes_options.php     /var/www/spip/config/mes_options.php

# Listen on 8080 so the container can run entirely unprivileged: a non-root
# process cannot bind 80, and Apache cannot drop privileges it never had.
# Runtime state dirs are handed to the runtime user for the same reason.
RUN set -eux; \
    a2enconf zz-hardening; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    chown -R "$UID:$GID" /var/run/apache2 /var/lock/apache2; \
    chmod 0444 /var/www/spip/config/mes_options.php \
               /usr/local/etc/php/conf.d/zz-spip-hardening.ini \
               /usr/local/etc/php/opcache-blacklist.txt \
               /etc/apache2/sites-available/000-default.conf \
               /etc/apache2/conf-available/zz-hardening.conf

USER spip
WORKDIR /var/www/spip

VOLUME ["/var/www/spip/IMG", "/var/www/spip/local", "/var/spip/tmp"]

EXPOSE 8080

# Fails if PHP cannot start or an extension is missing — catches a broken rebuild
# before it takes traffic.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php -r 'exit(extension_loaded("gd") && extension_loaded("mysqli") ? 0 : 1);'

CMD ["apache2-foreground"]
