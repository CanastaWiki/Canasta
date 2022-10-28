#!/bin/bash

sleep 0.01
printf "\n\n===== update-volume-permissions.sh =====\n\n\n"

set -x

. /functions.sh

echo "Checking permissions of Mediawiki volume dir $MW_VOLUME..."
make_dir_writable "$MW_VOLUME"
