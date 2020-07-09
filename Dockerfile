FROM ubuntu:bionic as openssl-build
LABEL maintainer="Hans Rakers <h.rakers@global.leaseweb.com>"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      autoconf \
      file \
      g++ \
      gcc \
      gnupg \
      libc-dev \
      make \
      pkg-config \
      re2c \
      zlib1g-dev \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir ~/.gnupg; \
    echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf; \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 0E604491

# compile openssl, otherwise --with-openssl won't work
RUN set -eux; \
    OPENSSL_VERSION="1.0.2u"; \
    cd /tmp; \
    mkdir openssl; \
    curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz; \
    curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc; \
    gpg --verify openssl.tar.gz.asc; \
    tar -xzf openssl.tar.gz -C openssl --strip-components=1; \
    cd /tmp/openssl; \
    ./config no-ssl2 no-ssl3 zlib-dynamic -fPIC && make -j$(nproc) && make install_sw; \
    rm -rf /tmp/*

FROM ubuntu:bionic as curl-build

COPY --from=openssl-build "/usr/local/ssl/" "/usr/local/ssl/"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      autoconf \
      file \
      g++ \
      gcc \
      gnupg \
      libc-dev \
      make \
      pkg-config \
      re2c \
      zlib1g-dev \
      libnghttp2-dev \
      libpsl-dev \
      libidn2-dev \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir ~/.gnupg; \
    echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf; \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 5CC908FDB71E12C2

RUN set -eux; \
    CURL_VERSION="7.71.1"; \
    cd /tmp; \
    mkdir curl; \
    curl -sL "https://curl.haxx.se/download/curl-$CURL_VERSION.tar.gz" -o curl.tar.gz; \
    curl -sL "https://curl.haxx.se/download/curl-$CURL_VERSION.tar.gz.asc" -o curl.tar.gz.asc; \
    gpg --verify curl.tar.gz.asc; \
    tar -xzf curl.tar.gz -C curl --strip-components=1; \
    cd /tmp/curl; \
    ./configure --prefix=/usr/local/curl --disable-shared --enable-static --disable-dependency-tracking \
        --disable-symbol-hiding --enable-versioned-symbols \
        --disable-threaded-resolver --with-lber-lib=lber \
        --with-ssl=/usr/local/ssl \
        --with-nghttp2 \
        --disable-gssapi --disable-ldap --disable-ldaps --disable-libssh2 --disable-rtsp; \
    make -j$(nproc); \
    make install; \
    rm -rf /tmp/*

FROM ubuntu:bionic as php-build

COPY --from=openssl-build "/usr/local/ssl/" "/usr/local/ssl/"
COPY --from=curl-build "/usr/local/curl/" "/usr/local/curl/"

# build dependencies for php-5.3
# php 5.3 needs older autoconf
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf \
      autoconf2.13 \
      ca-certificates \
      curl \
      file \
      g++ \
      gcc \
      gnupg \
      libbz2-dev \
      libc-dev \
      libedit-dev \
      libidn2-dev \
      libmcrypt-dev \
      libnghttp2-dev \
      libpsl-dev \
      libreadline6-dev \
      librecode-dev \
      libsqlite3-dev \
      libssl-dev \
      libxml2-dev \
      make \
      pkg-config \
      re2c \
      xz-utils \
      zlib1g-dev \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 A4A9406876FCBD3C456770C88C718D3B5072E1F5
RUN set -xe \
  && mkdir ~/.gnupg && echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

ENV PHP_VERSION 5.3.29

ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# https://github.com/docker-library/php/issues/272
# -D_LARGEFILE_SOURCE and -D_FILE_OFFSET_BITS=64 (https://www.php.net/manual/en/intro.filesystem.php)
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

COPY docker-php-source /usr/local/bin/

# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN set -eux; \
      # Install MySQL 5.7 client library and headers (the system package is compiled against OpenSSL 1.1, which we can't use)
      cd /usr/src; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb" -o libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb.asc" -o libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb" -o libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb.asc" -o libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/mysql-common_5.7.30-1ubuntu18.04_amd64.deb" -o mysql-common_5.7.30-1ubuntu18.04_amd64.deb; \
      curl -SL "http://mirror.nl.leaseweb.net/mysql/Downloads/MySQL-5.7/mysql-common_5.7.30-1ubuntu18.04_amd64.deb.asc" -o mysql-common_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      gpg --verify libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      gpg --verify libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      gpg --verify mysql-common_5.7.30-1ubuntu18.04_amd64.deb.asc; \
      dpkg -i libmysqlclient-dev_5.7.30-1ubuntu18.04_amd64.deb libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb mysql-common_5.7.30-1ubuntu18.04_amd64.deb; \
      curl -SL "http://nl.php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz; \
      curl -SL "http://nl.php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc; \
      gpg --verify php.tar.xz.asc; \
      docker-php-source extract; \
      cd /usr/src/php; \
      export \
        CFLAGS="$PHP_CFLAGS" \
        CPPFLAGS="$PHP_CPPFLAGS" \
        LDFLAGS="$PHP_LDFLAGS"; \
      ./configure \
          --with-config-file-path="$PHP_INI_DIR" \
          --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
          --enable-fpm \
          --with-fpm-user=www-data \
          --with-fpm-group=www-data \
          --disable-cgi \
          --with-curl=/usr/local/curl \
          --with-openssl=/usr/local/ssl \
          --with-readline \
          --with-recode \
          --with-zlib \
          --with-bz2 \
          --with-gettext \
          --with-mcrypt \
          --with-mhash \
          --with-mysql \
          --with-pdo-mysql \
          --with-pdo-sqlite=/usr \
          --with-sqlite3=/usr \
          --with-libedit \
          --with-zlib \
          --enable-bcmath \
          --enable-ftp \
          --enable-intl \
          --enable-mbstring \
          --enable-mysqlnd \
          --enable-soap \
          --enable-zip \
          ${PHP_EXTRA_CONFIGURE_ARGS:-}; \
      sed -i '/EXTRA_LIBS = /s|$| -lstdc++|' Makefile; \
      make -j$(nproc); \
      find -type f -name '*.a' -delete

FROM ubuntu:bionic

COPY --from=php-build "/usr/src/" "/usr/src/"

COPY docker-php-* /usr/local/bin/

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
	{ \
          echo 'Package: php*'; \
          echo 'Pin: release *'; \
          echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# persistent / runtime deps and deps required for compiling extensions
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      autoconf \
      binutils \
      ca-certificates \
      curl \
      file \
      g++ \
      gcc \
      gnupg \
      libc-dev \
      libedit2 \
      libidn2-0 \
      libnghttp2-14 \
      librecode0 \
      libmcrypt4 \
      libpsl5 \
      libreadline7 \
      libsqlite3-0 \
      libxml2 \
      make \
      pkg-config \
      re2c \
      xz-utils \
    ; \
    # Install MySQL 5.7 client library and headers (the system package is compiled against OpenSSL 1.1)
    cd /usr/src; \
    dpkg -i libmysqlclient20_5.7.30-1ubuntu18.04_amd64.deb mysql-common_5.7.30-1ubuntu18.04_amd64.deb; \
    rm /usr/src/*amd64.deb*; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php

RUN set -eux; \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
    [ ! -d /var/www/html ]; \
    mkdir -p /var/www/html; \
    chown www-data:www-data /var/www/html; \
    chmod 777 /var/www/html; \
    cd /usr/src/php; \
    make install; \
    { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; }; \
    make clean; \
    cp -v php.ini-* "$PHP_INI_DIR/"; \
    cd /; \
    docker-php-source delete; \
    pecl update-channels; \
    rm -rf /tmp/pear ~/.pearrc; \
    php --version

ENTRYPOINT ["docker-php-entrypoint"]
WORKDIR /var/www/html

RUN set -eux; \
  rm -f /usr/local/bin/phar; \
  ln -s /usr/local/bin/phar.phar /usr/local/bin/phar; \
  cd /usr/local/etc; \
  if [ -d php-fpm.d ]; then \
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
  fi; \
  { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo; \
    echo '[www]'; \
    echo '; if we send this to /proc/self/fd/1, it never appears'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo; \
    echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
    echo 'catch_workers_output = yes'; \
  } | tee php-fpm.d/docker.conf; \
  { \
    echo '[global]'; \
    echo 'daemonize = no'; \
    echo; \
    echo '[www]'; \
    echo 'listen = 9000'; \
  } | tee php-fpm.d/zz-docker.conf

# fix some weird corruption in this file
RUN sed -i -e "" /usr/local/etc/php-fpm.d/www.conf

# Override stop signal to stop process gracefully
# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

EXPOSE 9000
CMD ["php-fpm"]
