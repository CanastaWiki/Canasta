#!/bin/bash

set -x

. /functions.sh

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
protect_config

# Create needed directories
mkdir -p "$MW_VOLUME"/l10n_cache

/update-composer-deps.sh

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

# Skip when PHP_LOG_DIR is unset — an empty path makes mountpoint test "/"
# (always a mountpoint) and then runs chgrp/chmod on '', which errors every boot.
if [ -z "$PHP_LOG_DIR" ]; then
    echo "PHP_LOG_DIR is unset — skipping PHP-FPM log dir setup."
else
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
fi

config_subdir_wikis() {
    echo "Configuring subdirectory wikis..."
    /config-subdir-wikis.sh
    echo "Configured subdirectory wikis..."
}

create_storage_dirs() {
    echo "Creating cache, images, and public_assets dirs..."
    /create-storage-dirs.sh
    echo "Created cache, images, and public_assets dirs..."
}

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

########## Run maintenance scripts ##########
# Create storage directories early (before LocalSettings check) since wikis.yaml
# exists before install.php runs, and we need these directories to exist for uploads
if [ -e "$MW_VOLUME/config/wikis.yaml" ]; then
  create_storage_dirs
fi

echo "Checking for MediaWiki configuration..."
if [ -n "$MW_SECRET_KEY" ] || [ -e "$MW_VOLUME/config/LocalSettings.php" ] || [ -e "$MW_VOLUME/config/CommonSettings.php" ]; then
  # Snapshot which wikis have SMW set up before run_autoupdate, since
  # update.php triggers setupStore.php via SMW hooks (creating .smw.json
  # entries). We need to detect newly-setup wikis to notify the user.
  SMW_JSON="$MW_VOLUME/config/persistent/.smw.json"
  if [ -f "$MW_HOME/extensions/SemanticMediaWiki/extension.json" ]; then
    mkdir -p "$MW_VOLUME/config/persistent"
    # Heal config/persistent ownership before run_autoupdate so setupStore.php
    # (invoked by update.php) can write .smw.json. The make_dir_writable on the
    # writable volume dirs runs later and in the background — too late for
    # setupStore on this start. Scoped to just this directory to stay cheap.
    make_dir_writable "$MW_VOLUME/config/persistent"
    SMW_WIKIS_BEFORE=""
    if [ -f "$SMW_JSON" ]; then
      SMW_WIKIS_BEFORE=$(php -r "
        \$data = json_decode(file_get_contents('$SMW_JSON'), true) ?? [];
        echo implode('\n', array_keys(\$data));
      ")
    fi
  fi

  # Run auto-update (LocalSettings.php/CommonSettings.php checks are for backward compatibility)
  . /run-maintenance-scripts.sh
  if isTrue "$MW_AUTOUPDATE"; then
    run_autoupdate
  else
    echo "Auto update script is disabled, MW_AUTOUPDATE is $MW_AUTOUPDATE"
  fi
  create_sessions_tables

  # Notify if SMW was newly set up and needs rebuildData.
  # setupStore.php (run by update.php hooks) creates tables but does not
  # populate them — rebuildData.php is needed for Special:Browse etc.
  # We don't run it automatically because it can take a very long time on
  # large wikis and users may need to run it in segments with custom options.
  if [ -f "$MW_HOME/extensions/SemanticMediaWiki/extension.json" ]; then
    smw_needs_rebuild=false
    wiki_ids=$(get_wiki_ids)
    if [ -n "$wiki_ids" ]; then
      while IFS= read -r wiki_id; do
        if [ -n "$wiki_id" ]; then
          if ! echo "$SMW_WIKIS_BEFORE" | grep -qx "$wiki_id"; then
            smw_needs_rebuild=true
            break
          fi
        fi
      done <<< "$wiki_ids"
    else
      if [ -z "$SMW_WIKIS_BEFORE" ] && [ -f "$SMW_JSON" ]; then
        smw_needs_rebuild=true
      fi
    fi
    if [ "$smw_needs_rebuild" = true ]; then
      echo ""
      echo "========================================================================"
      echo "NOTE: Semantic MediaWiki was newly set up. You need to run rebuildData"
      echo "to populate the SMW store. Use: canasta maintenance smw-rebuild"
      echo "========================================================================"
      echo ""
    fi
  fi
fi

# Configure Apache rewrites for path-based wikis (e.g., localhost/wiki2)
if [ -e "$MW_VOLUME/config/wikis.yaml" ]; then
  config_subdir_wikis
fi

echo "Starting services..."

# Run maintenance scripts in background.
touch "$WWW_ROOT/.maintenance"
/run-maintenance-scripts.sh &

echo "Checking permissions of Mediawiki log dir $MW_LOG..."
if ! mountpoint -q -- "$MW_LOG"; then
    mkdir -p "$MW_VOLUME/log/mediawiki"
    rsync -avh --ignore-existing "$MW_LOG/" "$MW_VOLUME/log/mediawiki/"
    mv "$MW_LOG" "${MW_LOG}_old"
    ln -s "$MW_VOLUME/log/mediawiki" "$MW_LOG"
    chgrp -R "$WWW_GROUP" "$MW_VOLUME/log/mediawiki"
    chmod -R g=rwX "$MW_VOLUME/log/mediawiki"
else
    chgrp -R "$WWW_GROUP" "$MW_LOG"
    chmod -R go=rwX "$MW_LOG"
fi

echo "Checking permissions of the writable MediaWiki volume dirs..."
writable_dirs=()
for dir in cache l10n_cache extensions skins public_assets config/persistent; do
    [ -d "$MW_VOLUME/$dir" ] && writable_dirs+=("$MW_VOLUME/$dir")
done
[ ${#writable_dirs[@]} -gt 0 ] && make_dir_writable "${writable_dirs[@]}" &

# Running php-fpm
/run-php-fpm.sh &

############### Run Apache ###############
# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/apache2/* /tmp/apache2*

# Exec apache2 itself rather than apachectl, whose shell would stay PID 1
# and never pass the container's stop signal on to Apache.
. /etc/apache2/envvars
install -d "$APACHE_RUN_DIR"
install -d -o "$APACHE_RUN_USER" "$APACHE_RUN_DIR/socks" "$APACHE_LOCK_DIR"
exec /usr/sbin/apache2 -DFOREGROUND
