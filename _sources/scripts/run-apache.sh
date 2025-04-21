#!/bin/bash

date=$(date -u +%Y%m%d_%H%M%S)
BOOTSTRAP_LOGFILE="$MW_LOG/_bootstrap_$date.log"
export BOOTSTRAP_LOGFILE

echo "==== STARTING $date ===="
echo "See Bash XTrace in the $BOOTSTRAP_LOGFILE file"

echo "Checking permissions of Mediawiki log dir $MW_LOG..."
if ! mountpoint -q -- "$MW_LOG"; then
    mkdir -p "$MW_VOLUME/log/mediawiki"
    rsync -avh --ignore-existing "$MW_LOG/" "$MW_VOLUME/log/mediawiki/"
    mv "$MW_LOG" "${MW_LOG}_old"
    ln -s "$MW_VOLUME/log/mediawiki" "$MW_LOG"
    chmod -R o=rwX "$MW_VOLUME/log/mediawiki"
else
    chgrp -R "$WWW_GROUP" "$MW_LOG"
    chmod -R go=rwX "$MW_LOG"
fi

# Open file descriptor 3 for logging xtrace output
exec 3> >(stdbuf -oL tee -a "$BOOTSTRAP_LOGFILE" >/dev/null)

# Redirect stdout and stderr to the log file using tee,
# with stdbuf to handle buffering issues
exec > >(stdbuf -oL tee -a "$BOOTSTRAP_LOGFILE") 2>&1

# Enable xtrace and Redirect the xtrace output to log file only
BASH_XTRACEFD=3
set -x

. /functions.sh

if ! mountpoint -q -- "$MW_VOLUME"; then
    echo "Folder $MW_VOLUME contains important data and must be mounted to persistent storage!"
    if ! isTrue "$MW_ALLOW_UNMOUNTED_VOLUME"; then
        exit 1
    fi
    echo "You allowed to continue because MW_ALLOW_UNMOUNTED_VOLUME is set as true"
fi

# Symlink all extensions and skins (both bundled and user)
/create-symlinks.sh

# Soft sync contents from $MW_ORIGIN_FILES directory to $MW_VOLUME
# The goal of this operation is to copy over all the files generated
# by the image to bind-mount points on host which are bind to
# $MW_VOLUME (./extensions, ./skins, ./config, ./images),
# note that this command will also set all the necessary permissions
echo "Syncing files..."
rsync -ah --inplace --ignore-existing \
  -og --chown="$WWW_GROUP:$WWW_USER" --chmod=Fg=rw,Dg=rwx \
  "$MW_ORIGIN_FILES"/ "$MW_VOLUME"/

# Create needed directories
mkdir -p "$MW_VOLUME"/extensions/SemanticMediaWiki/config
mkdir -p "$MW_VOLUME"/l10n_cache

echo "PHP_ERROR_REPORTING environment variable is set to: $PHP_ERROR_REPORTING"
# Update PHP configuration files with error reporting settings
# First remove any existing error_reporting line, then add the new one
sed -i '/^error_reporting/d' /etc/php/7.4/cli/conf.d/php_cli_error_reporting.ini
sed -i '/; error_reporting will be calculated in the run-apache.sh script and inserted below/a error_reporting = '"$PHP_ERROR_REPORTING" /etc/php/7.4/cli/conf.d/php_cli_error_reporting.ini
sed -i '/^error_reporting/d' /etc/php/7.4/fpm/conf.d/php_error_reporting.ini
sed -i '/; error_reporting will be calculated in the run-apache.sh script and inserted below/a error_reporting = '"$PHP_ERROR_REPORTING" /etc/php/7.4/fpm/conf.d/php_error_reporting.ini

printf "\nCheck wiki settings for errors... "
if ! php /getMediawikiSettings.php --version MediaWiki; then
    printf "\n===================================== ERROR ======================================\n\n"
    echo "An error occurred while checking the wiki settings."
    echo "There is an error in the wiki settings files, or you missed to run the \"git submodule update --init --recursive\" command"
    printf "\n==================================================================================\n\n"
    exit 1
else
    printf " OK\n\n"
fi

/update-docker-gateway.sh

# Permissions
# Note: this part if checking for root directories permissions
# assuming that if the root directory has correct permissions set
# it's in result of previous success run of this code or this code
# was executed by another container (in case mount points are shared)
# hence it does not perform any recursive checks and may lead to files
# or directories down the tree having incorrect permissions left untouched

# Write log files to $MW_VOLUME/log directory if target folders are not mounted
echo "Checking permissions of Apache log dir $APACHE_LOG_DIR..."
if ! mountpoint -q -- "$APACHE_LOG_DIR/"; then
    mkdir -p "$MW_VOLUME/log/httpd"
    rsync -avh --ignore-existing "$APACHE_LOG_DIR/" "$MW_VOLUME/log/httpd/"
    mv "$APACHE_LOG_DIR" "${APACHE_LOG_DIR}_old"
    ln -s "$MW_VOLUME/log/httpd" "$APACHE_LOG_DIR"
else
    chgrp -R "$WWW_GROUP" "$APACHE_LOG_DIR"
    chmod -R g=rwX "$APACHE_LOG_DIR"
fi

echo "Checking permissions of PHP-FPM log dir $PHP_LOG_DIR..."
if ! mountpoint -q -- "$PHP_LOG_DIR/"; then
    mkdir -p "$MW_VOLUME/log/php-fpm"
    rsync -avh --ignore-existing "$PHP_LOG_DIR/" "$MW_VOLUME/log/php-fpm/"
    mv "$PHP_LOG_DIR" "${PHP_LOG_DIR}_old"
    ln -s "$MW_VOLUME/log/php-fpm" "$PHP_LOG_DIR"
else
    chgrp -R "$WWW_GROUP" "$PHP_LOG_DIR"
    chmod -R g=rwX "$PHP_LOG_DIR"
fi

echo "Checking permissions of Mediawiki volume dir $MW_VOLUME except $MW_VOLUME/images..."
make_dir_writable "$MW_VOLUME" -not '(' -path "$MW_VOLUME/images" -prune ')'

check_mount_points () {
  # Check for $MW_HOME/user-extensions presence and bow out if it's not in place
  if [ ! -d "$MW_HOME/user-extensions" ]; then
    echo "WARNING! As of Canasta 1.2.0, $MW_HOME/user-extensions is the correct mount point! Please update your Docker Compose stack to 1.2.0, which will re-mount to $MW_HOME/user-extensions."
    exit 1
  fi

  # Check for $MW_HOME/user-skins presence and bow out if it's not in place
  if [ ! -d "$MW_HOME/user-skins" ]; then
    echo "WARNING! As of Canasta 1.2.0, $MW_HOME/user-skins is the correct mount point! Please update your Docker Compose stack to 1.2.0, which will re-mount to $MW_HOME/user-skins."
    exit 1
  fi
}

# Check for `user-` prefixed mounts and bow out if not found
check_mount_points

sleep 1
cd "$MW_HOME" || exit

# Check and update permissions of wiki images in background.
# It can take a long time and should not block Apache from starting.
/update-images-permissions.sh &

/monitor-directories.sh &

# Run maintenance scripts in background.
touch "$WWW_ROOT/.maintenance"
/run-maintenance-scripts.sh &

# Running php-fpm
/run-php-fpm.sh &

############### Run Apache ###############
# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/apache2/* /tmp/apache2*

printf "\n\n==================================================================================\n\n\n"

exec /usr/sbin/apachectl -DFOREGROUND
