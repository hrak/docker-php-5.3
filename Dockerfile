FROM ubuntu:xenial as openssl-build
MAINTAINER Hans Rakers <h.rakers@global.leaseweb.com>

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 0E604491

# compile openssl, otherwise --with-openssl won't work
RUN OPENSSL_VERSION="1.0.2p" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config && make -j$(nproc) && make install_sw \
      && rm -rf /tmp/*

FROM ubuntu:xenial as php-build

COPY --from=openssl-build "/usr/local/ssl/" "/usr/local/ssl/"

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      librecode0 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libxml2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# phpize deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

ENV PHP_VERSION 5.3.29

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
                autoconf2.13 \
                libbz2-dev \
                libcurl4-openssl-dev \
                libmcrypt-dev \
                libreadline6-dev \
                librecode-dev \
                libsqlite3-dev \
                libssl-dev \
                libxml2-dev \
                xz-utils \
      " \
      && set -x \
      && apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
      && curl -SL "http://nl.php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && curl -SL "http://nl.php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
      && gpg --verify php.tar.xz.asc \
      && mkdir -p /usr/src/php \
      && tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
      && rm php.tar.xz* \
      && cd /usr/src/php \
      && ./configure \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-fpm \
            --with-fpm-user=www-data \
            --with-fpm-group=www-data \
            --disable-cgi \
            --enable-mysqlnd \
            --with-mysql \
            --with-curl \
            --with-openssl=/usr/local/ssl \
            --with-readline \
            --with-recode \
            --with-zlib \
            --with-bz2 \
            --with-gettext \
            --with-mcrypt \
            --with-mhash \
            --with-pdo-mysql \
            --enable-bcmath \
            --enable-ftp \
            --enable-intl \
            --enable-mbstring \
            --enable-soap \
            --enable-zip \
      && sed -i '/EXTRA_LIBS = /s|$| -lstdc++|' Makefile \
      && make -j$(nproc)

FROM ubuntu:xenial

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      binutils \
      ca-certificates \
      libcurl3 \
      librecode0 \
      libmcrypt4 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libxml2 \
      make \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=php-build "/usr/src/php/" "/usr/src/php/"
COPY --from=php-build "/usr/local/etc/php/" "/usr/local/etc/php/"

RUN cd /usr/src/php \
    && make install \
    && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
    && make clean

# COPY --from=php-build "/usr/local/php/" "/usr/local/"
COPY docker-php-* /usr/local/bin/

ENTRYPOINT ["docker-php-entrypoint"]
WORKDIR /var/www/html

RUN set -ex \
  && rm -f /usr/local/bin/phar \
  && ln -s /usr/local/bin/phar.phar /usr/local/bin/phar \
  && cd /usr/local/etc \
  && if [ -d php-fpm.d ]; then \
    # for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
    sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
    cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
  else \
    # PHP 5.x don't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
    mkdir php-fpm.d; \
    cp php-fpm.conf.default php-fpm.d/www.conf; \
    { \
      echo '[global]'; \
      echo 'include=etc/php-fpm.d/*.conf'; \
    } | tee php-fpm.conf; \
  fi \
  && { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo; \
    echo '[www]'; \
    echo '; if we send this to /proc/self/fd/1, it never appears'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo; \
    echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
    echo 'catch_workers_output = yes'; \
  } | tee php-fpm.d/docker.conf \
  && { \
    echo '[global]'; \
    echo 'daemonize = no'; \
    echo; \
    echo '[www]'; \
    echo 'listen = 9000'; \
  } | tee php-fpm.d/zz-docker.conf \
  && pecl update-channels \
  && rm -rf /tmp/pear ~/.pearrc \
  && php --version

# fix some weird corruption in this file
RUN sed -i -e "" /usr/local/etc/php-fpm.d/www.conf

EXPOSE 9000
CMD ["php-fpm"]
