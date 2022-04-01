#!/bin/bash

set -x

# read variables from LocalSettings.php
get_mediawiki_variable () {
    php /getMediawikiSettings.php --variable="$1" --format="${2:-string}"
}

dir_is_writable() {
  # Use -L to get information about the target of a symlink,
  # not the link itself, as pointed out in the comments
  INFO=( $(stat -L -c "0%a %G %U" "$1") )
  PERM=${INFO[0]}
  GROUP=${INFO[1]}
  OWNER=${INFO[2]}

  if (( ($PERM & 0002) != 0 )); then
      # Everyone has write access
      return 0
  elif (( ($PERM & 0020) != 0 )); then
      # Some group has write access.
      # Is user in that group?
      if [[ $GROUP == $WWW_GROUP ]]; then
          return 0
      fi
  elif (( ($PERM & 0200) != 0 )); then
      # The owner has write access.
      # Does the user own the file?
      [[ $WWW_USER == $OWNER ]] && return 0
  fi

  return 1
}

# Soft sync contents from $MW_ORIGIN_FILES directory to $MW_VOLUME
# The goal of this operation is to copy over all the files generated
# by the image to bind-mount points on host which are bind to
# $MW_VOLUME (./extensions, ./skins, ./config, ./images),
# note that this command will also set all the necessary permissions
echo "Syncing files.."
rsync -ah --inplace --ignore-existing --remove-source-files \
  -og --chown=$WWW_GROUP:$WWW_USER --chmod=Fg=rw,Dg=rwx \
  "$MW_ORIGIN_FILES"/ "$MW_VOLUME"/

# We don't need it anymore
rm -rf "$MW_ORIGIN_FILES"

# Map host for VisualEditor
if [ -e "$MW_VOLUME/config/LocalSettings.php"  ]; then
  MW_SITE_SERVER=$(get_mediawiki_variable wgServer)
  if [[ ! $MW_SITE_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DOMAIN=$(echo "$MW_SITE_SERVER" | sed -e 's|^[^/]*//||' -e 's|[:/].*$||')
    echo "172.17.0.1 $DOMAIN" >> /etc/hosts
  fi
fi

# Permissions
# Note: this part if checking for root directories permissions
# assuming that if the root directory has correct permissions set
# it's in result of previous success run of this code or this code
# was executed by another container (in case mount points are shared)
# hence it does not perform any recursive checks and may lead to files
# or directories down the tree having incorrect permissions left untouched

echo "Checking permissions of $MW_VOLUME.."
if dir_is_writable $MW_VOLUME; then
  echo "Permissions are OK!"
else
  chown -R "$WWW_GROUP":"$WWW_GROUP" "$MW_VOLUME"
  chmod -R g=rwX "$MW_VOLUME"
fi

echo "Checking permissions of $APACHE_LOG_DIR.."
if dir_is_writable $APACHE_LOG_DIR; then
  echo "Permissions are OK!"
else
  chown -R "$WWW_GROUP":"$WWW_GROUP" $APACHE_LOG_DIR
  chmod -R g=rwX $APACHE_LOG_DIR
fi

jobrunner() {
    sleep 3
    if [ "$MW_ENABLE_JOB_RUNNER" = true ]; then
        echo >&2 Run Jobs
        nice -n 20 runuser -c /mwjobrunner.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Job runner is disabled
    fi
}

transcoder() {
    sleep 3
    if [ "$MW_ENABLE_TRANSCODER" = true ]; then
        echo >&2 Run transcoder
        nice -n 20 runuser -c /mwtranscoder.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Transcoder disabled
    fi
}

sitemapgen() {
    sleep 3
    if [ "$MW_ENABLE_SITEMAP_GENERATOR" = true ]; then
        # Fetch & export script path for sitemap generator
        if [ -z "$MW_SCRIPT_PATH" ]; then
          MW_SCRIPT_PATH=$(get_mediawiki_variable wgScriptPath)
        fi
        # Fall back to default value if can't fetch the variable
        if [ -z "$MW_SCRIPT_PATH" ]; then
          MW_SCRIPT_PATH="/w"
        fi
        echo >&2 Run sitemap generator
        MW_SCRIPT_PATH=$MW_SCRIPT_PATH nice -n 20 runuser -c /mwsitemapgen.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Sitemap generator is disabled
    fi
}

waitdatabase() {
  /wait-for-it.sh -t 60 db:3306
}

#waitelastic() {
#  ./wait-for-it.sh -t 60 elasticsearch:9200
#}

run_autoupdate () {
    echo "Running Auto-update.."
    runuser -c "php maintenance/update.php --quick" -s /bin/bash "$WWW_USER"
    echo "Auto-update completed"
}

replace_env_var_in_composer_json_file() {
    sed -i 's#%MW_VOLUME%#'"$MW_VOLUME"'#g' "$MW_HOME/composer.local.json"
}

run_composer () {
  echo "Running Composer updates.."
  # The below command will do the following things:
  # 1. Install everything listed on $MW_HOME/composer.local.json both "require" and "merge-plugin" sections
  # 2. Install everything listed on $MW_VOLUME/config/composer.local.json "merge-plugin" section
  # 3. Wipe $MW_HOME/vendor/autoload_.. files and generate new ones
  # 4. All the extensions listed on the composer files above will land to $MW_HOME/extensions (not needed)
  # 4. All the skins listed on the composer files above will land to $MW_HOME/skins (not needed)

  # Due to "check_mount_points" method being called before this one we assume that
  # neither extensions nor skins directory does not exist, so we can
  # create temporary symlinks to match the original state for when the packages were installed during build stage
  cp -ar "$MW_HOME/canasta-extensions" "$MW_HOME/canasta-extensions-snapshot"
  cp -ar "$MW_HOME/canasta-skins" "$MW_HOME/canasta-skins-snapshot"
  # Symlink from snapshots to default paths used by composer/installers
  ln -s "$MW_HOME/canasta-extensions-snapshot" "$MW_HOME/extensions"
  ln -s "$MW_HOME/canasta-skins-snapshot" "$MW_HOME/skins"

  composer update --no-dev
  echo "Fixing up composer autoload files.."
  # Fix up future use of canasta-extensions directory for composer autoload
  sed -i 's/extensions/canasta-extensions/g' "$MW_HOME/vendor/composer/autoload_static.php" \
  && sed -i 's/extensions/canasta-extensions/g' "$MW_HOME/vendor/composer/autoload_files.php" \
  && sed -i 's/extensions/canasta-extensions/g' "$MW_HOME/vendor/composer/autoload_classmap.php" \
  && sed -i 's/extensions/canasta-extensions/g' "$MW_HOME/vendor/composer/autoload_psr4.php" \
  && sed -i 's/skins/canasta-skins/g' "$MW_HOME/vendor/composer/autoload_static.php" \
  && sed -i 's/skins/canasta-skins/g' "$MW_HOME/vendor/composer/autoload_files.php" \
  && sed -i 's/skins/canasta-skins/g' "$MW_HOME/vendor/composer/autoload_classmap.php" \
  && sed -i 's/skins/canasta-skins/g' "$MW_HOME/vendor/composer/autoload_psr4.php"
  # Wipe symlinks and snapshot directories
  rm "$MW_HOME/extensions"
  rm "$MW_HOME/skins"
  rm -rf "$MW_HOME/canasta-extensions-snapshot"
  rm -rf "$MW_HOME/canasta-skins-snapshot"
  # Fix permissions
  #! chown -R "$WWW_GROUP":"$WWW_GROUP" "$MW_HOME"
  # Done
  echo "Composer updates completed"
}

check_mount_points () {
  # Check for $MW_HOME/extensions presence and bow out if it's in place
  if [ -d "$MW_HOME/extensions" ]; then
    # Do no composer updates if the directory is in place because this means that
    # the directory is probably mounted from host and the mount point was not updated to user-extensions
    echo "WARNING! $MW_HOME/extensions is an incorrect mount point, please re-mount to $MW_HOME/user-extensions"
    exit 1
  fi

  # Check for $MW_HOME/extensions presence and bow out if it's in place
  if [ -d "$MW_HOME/skins" ]; then
    # Do no composer updates if the directory is in place because this means that
    # the directory is probably mounted from host and the mount point was not updated to user-extensions
    echo "WARNING! $MW_HOME/skins is an incorrect mount point, please re-mount to $MW_HOME/user-skins"
    exit 1
  fi
}

# Wait db
waitdatabase

replace_env_var_in_composer_json_file

# Warning! This is a breaking change, this check will prevent the container from starting on
# outdated extensions and skins directories mounting scheme
check_mount_points

sleep 1
cd "$MW_HOME" || exit

########## Run Composer updates #############
echo "Checking for custom composer.local.json file.."
if [ -e "$MW_VOLUME/config/composer.local.json" ]; then
  run_composer
fi

########## Run maintenance scripts ##########
echo "Checking for LocalSettings.."
if [ -e "$MW_VOLUME/config/LocalSettings.php"  ]; then
  # Run auto-update
  run_autoupdate
fi

echo "Starting services.."
jobrunner &
transcoder &
sitemapgen &

############### Run Apache ###############
# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/httpd/* /tmp/httpd*

exec /usr/sbin/apachectl -DFOREGROUND
