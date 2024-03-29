#!/bin/bash

sleep 0.01
printf "\n\n===== update-images-permissions.sh =====\n\n\n"

set -x

. /functions.sh

echo "Checking permissions of images in Mediawiki volume dir $MW_VOLUME/images..."
make_dir_writable "$MW_VOLUME/images"
