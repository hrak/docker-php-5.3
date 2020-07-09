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
