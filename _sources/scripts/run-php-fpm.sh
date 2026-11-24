#!/bin/bash

set -x

echo "starting php-fpm"
# Running php-fpm
mkdir -p /run/php
exec /usr/sbin/php-fpm8.2