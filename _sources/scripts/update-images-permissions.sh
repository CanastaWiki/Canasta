#!/bin/bash

sleep 0.01

# Check if BOOTSTRAP_LOGFILE is defined and not empty
if [ -n "$BOOTSTRAP_LOGFILE" ]; then
    # If BOOTSTRAP_LOGFILE is defined, set up logging
    # Open file descriptor 3 for logging xtrace output
    exec 3>>"$BOOTSTRAP_LOGFILE"
    BASH_XTRACEFD=3
fi
set -x

printf "\n\n===== update-images-permissions.sh =====\n\n\n"

. /functions.sh

echo "Checking permissions of images in Mediawiki volume dir $MW_VOLUME/images..."
make_dir_writable "$MW_VOLUME/images"
