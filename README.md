# docker-php-5.3
PHP-5.3.29 in a Ubuntu 18.04 container for legacy applications. Loosely based on the last official php Dockerfile for PHP-5.3,
it uses a multi-stage build for compilation of OpenSSL 1.0, curl and PHP.

## But... Why?

Because we have some legacy Symfony apps running that will eventually be phased out, and are not worth rewriting. These apps can now be isolated, allowing us to keep the underlying OS up-to-date.

## Current versions used
* Ubuntu 18.04
* PHP 5.3.29
* OpenSSL 1.0.2u
* Curl 7.71.1
* MySQL 5.7.30

See the [README](https://github.com/docker-library/docs/blob/master/php/README.md) of the official PHP Docker image for information on how to use this image.

## Differences with the original image

There are three deviations from the original image.

* This image contains a backported patch to fpm that changes the order in which configuration files are included from `/usr/local/etc/php-fpm.d`. By default in PHP 5.3 there was no sorting on the glob, causing files to be included in whatever order they appeared in the filesystem, which can differ from system to system. The patch removes the `GLOB_NOSORT` from the call to glob(), causing the files to be included in a alphabetic order. See [Dockerfile](Dockerfile) for details.

* This image also allows you to override the default listen directive of fpm. By default, it will listen on `0.0.0.0:9000`, but you can override this using the environment variable `PHP_FPM_LISTEN`. For example:

```
docker run -it -e PHP_FPM_LISTEN="localhost:9000" hrak/php-5.3:latest
```

* Zend Opcache is included (extension load, but not enabled by default). You can enable and configure it through php.ini
