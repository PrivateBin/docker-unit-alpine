FROM alpine:3.18.3

ARG ALPINE_PACKAGES="php82-iconv php82-pdo_mysql php82-pdo_pgsql php82-openssl php82-simplexml"
ARG COMPOSER_PACKAGES="aws/aws-sdk-php google/cloud-storage"
ARG PBURL=https://github.com/PrivateBin/PrivateBin/
ARG RELEASE=1.5.2
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
        ALPINE_COMPOSER_PACKAGES="php82-phar" ;\
        if [ -n "${ALPINE_PACKAGES##*php82-curl*}" ] ; then \
            ALPINE_COMPOSER_PACKAGES="php82-curl ${ALPINE_COMPOSER_PACKAGES}" ;\
        fi ;\
        if [ -n "${ALPINE_PACKAGES##*php82-mbstring*}" ] ; then \
            ALPINE_COMPOSER_PACKAGES="php82-mbstring ${ALPINE_COMPOSER_PACKAGES}" ;\
        fi ;\
        RAWURL="$(echo ${PBURL} | sed s/github.com/raw.githubusercontent.com/)" ;\
    fi \
# Install dependencies
    && apk upgrade --no-cache \
    && apk add --no-cache gnupg git php82 php82-gd php82-opcache tzdata \
        unit-php82 ${ALPINE_PACKAGES} ${ALPINE_COMPOSER_PACKAGES} \
# Stabilize php config location
    && mv /etc/php82 /etc/php \
    && ln -s /etc/php /etc/php82 \
    && ln -s $(which php82) /usr/local/bin/php \
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
    && if [ -n "${COMPOSER_PACKAGES}" ] ; then \
        wget -qO composer-installer.php https://getcomposer.org/installer \
        && php composer-installer.php --install-dir=/usr/local/bin --filename=composer ;\
    fi \
    && mkdir -p /srv/data /srv/www \
    && cd /srv/www \
    && tar -xzf /tmp/${RELEASE}.tar.gz --strip 1 \
    && if [ -n "${COMPOSER_PACKAGES}" ] ; then \
        wget -q ${RAWURL}${RELEASE}/composer.json \
        && wget -q ${RAWURL}${RELEASE}/composer.lock \
        && composer remove --dev --no-update phpunit/phpunit \
        && composer require --no-update ${COMPOSER_PACKAGES} \
        && composer update --no-dev --optimize-autoloader \
        rm composer.* /usr/local/bin/* ;\
    fi \
    && rm *.md cfg/conf.sample.php .htaccess* */.htaccess \
    && mv bin cfg lib tpl vendor /srv \
    && sed -i "s#define('PATH', '');#define('PATH', '/srv/');#" index.php \
# Support running unit under a non-root user
    && chown -R ${UID}:${GID} /run /srv/* /var/lib/unit \
# Clean up
    && gpgconf --kill gpg-agent \
    && rm -rf /tmp/* \
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
