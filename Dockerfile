FROM alpine:3.22

ARG ALPINE_PACKAGES="php84-iconv php84-pdo_mysql php84-pdo_pgsql php84-openssl php84-simplexml"
ARG COMPOSER_PACKAGES="aws/aws-sdk-php google/cloud-storage"
ARG PBURL=https://github.com/PrivateBin/PrivateBin/
ARG RELEASE=1.7.6
ARG UID=65534
ARG GID=82

ENV CONFIG_PATH=/srv/cfg
ENV PATH=$PATH:/srv/bin

LABEL org.opencontainers.image.authors=support@privatebin.org \
      org.opencontainers.image.vendor=PrivateBin \
      org.opencontainers.image.documentation=https://github.com/PrivateBin/docker-unit-alpine/blob/master/README.md \
      org.opencontainers.image.source=https://github.com/PrivateBin/docker-unit-alpine \
      org.opencontainers.image.licenses=zlib-acknowledgement \
      org.opencontainers.image.version=${RELEASE}

COPY release.asc /tmp/

RUN \
# Prepare composer dependencies
    ALPINE_PACKAGES="$(echo ${ALPINE_PACKAGES} | sed 's/,/ /g')" ;\
    ALPINE_COMPOSER_PACKAGES="" ;\
    if [ -n "${COMPOSER_PACKAGES}" ] ; then \
        # we need these PHP 8.3 packages until composer gets updated to depend on PHP 8.4
        ALPINE_COMPOSER_PACKAGES="composer" ;\
        if [ -n "${ALPINE_PACKAGES##*php83-curl*}" ] ; then \
            ALPINE_COMPOSER_PACKAGES="php83-curl ${ALPINE_COMPOSER_PACKAGES}" ;\
        fi ;\
        if [ -n "${ALPINE_PACKAGES##*php83-mbstring*}" ] ; then \
            ALPINE_COMPOSER_PACKAGES="php83-mbstring ${ALPINE_COMPOSER_PACKAGES}" ;\
        fi ;\
        if [ -z "${ALPINE_PACKAGES##*php84-simplexml*}" ] ; then \
            ALPINE_COMPOSER_PACKAGES="php83-simplexml ${ALPINE_COMPOSER_PACKAGES}" ;\
        fi ;\
    fi \
# Install dependencies
    && apk upgrade --no-cache \
    && apk add --no-cache gnupg git php84 php84-ctype php84-gd php84-opcache \
        tzdata unit-php84 ${ALPINE_PACKAGES} ${ALPINE_COMPOSER_PACKAGES} \
# Stabilize php config location
    && mv /etc/php84 /etc/php \
    && ln -s /etc/php /etc/php84 \
    && ln -s $(which php84) /usr/local/bin/php \
# Install PrivateBin
    && cd /tmp \
    && export GNUPGHOME="$(mktemp -d -p /tmp)" \
    && gpg2 --list-public-keys || /bin/true \
    && gpg2 --import /tmp/release.asc \
    && if expr "${RELEASE}" : '[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}$' >/dev/null ; then \
         echo "getting release ${RELEASE}"; \
         wget -qO ${RELEASE}.tar.gz.asc ${PBURL}releases/download/${RELEASE}/PrivateBin-${RELEASE}.tar.gz.asc \
         && wget -q ${PBURL}archive/${RELEASE}.tar.gz \
         && gpg2 --verify ${RELEASE}.tar.gz.asc ; \
       else \
         echo "getting tarball for ${RELEASE}"; \
         git clone ${PBURL%%/}.git -b ${RELEASE}; \
         (cd $(basename ${PBURL}) && git archive --prefix ${RELEASE}/ --format tgz ${RELEASE} > /tmp/${RELEASE}.tar.gz); \
       fi \
    && mkdir -p /srv/data /srv/www \
    && cd /srv/www \
    && tar -xzf /tmp/${RELEASE}.tar.gz --strip 1 \
    && if [ -n "${COMPOSER_PACKAGES}" ] ; then \
        composer remove --dev --no-update phpunit/phpunit \
        && composer config --unset platform \
        && composer require --no-update ${COMPOSER_PACKAGES} \
        && composer update --no-dev --optimize-autoloader \
        rm /usr/local/bin/* ;\
    fi \
    && rm *.md cfg/conf.sample.php .htaccess* */.htaccess \
    && mv bin cfg lib tpl vendor /srv \
    && sed -i "s#define('PATH', '');#define('PATH', '/srv/');#" index.php \
# Support running unit under a non-root user
    && chown -R ${UID}:${GID} /run /srv/* /var/lib/unit \
# Clean up
    && gpgconf --kill gpg-agent \
    && rm -rf /tmp/* composer.* \
    && apk del --no-cache gnupg git ${ALPINE_COMPOSER_PACKAGES}

COPY --chown=${UID}:${GID} conf.json /var/lib/unit/

WORKDIR /srv/www
# user nobody, group www-data
USER ${UID}:${GID}

# mark dirs as volumes that need to be writable, allows running the container --read-only
VOLUME /run /srv/data /tmp /var/lib/unit

EXPOSE 8080

HEALTHCHECK CMD ["wget", "-qO/dev/null", "http://localhost:8080"]

ENTRYPOINT ["/usr/sbin/unitd"]

CMD ["--no-daemon", "--log", "/dev/stdout", "--tmpdir", "/tmp"]
