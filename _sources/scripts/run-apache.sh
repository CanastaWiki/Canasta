#!/bin/bash

set -x

# read variables from LocalSettings.php
get_mediawiki_variable () {
    php /getMediawikiSettings.php --variable="$1" --format="${2:-string}"
}

isTrue() {
    case $1 in
        "True" | "TRUE" | "true" | 1)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

isFalse() {
    case $1 in
        "True" | "TRUE" | "true" | 1)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
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

prepare_extensions_skins_symlinks() {
  echo "Symlinking bundled extensions..."
  for bundled_extension_path in $(find $MW_HOME/canasta-extensions/ -maxdepth 1 -mindepth 1 -type d)
  do
      bundled_extension_id=$(basename $bundled_extension_path)
      ln -s $MW_HOME/canasta-extensions/$bundled_extension_id/ $MW_HOME/extensions/$bundled_extension_id
  done
  echo "Symlinking bundled skins..."
  for bundled_skin_path in $(find $MW_HOME/canasta-skins/ -maxdepth 1 -mindepth 1 -type d)
  do
      bundled_skin_id=$(basename $bundled_skin_path)
      ln -s $MW_HOME/canasta-skins/$bundled_skin_id/ $MW_HOME/skins/$bundled_skin_id
  done
  echo "Symlinking user extensions and overwriting any redundant bundled extensions..."
  for user_extension_path in $(find $MW_HOME/user-extensions/ -maxdepth 1 -mindepth 1 -type d)
  do
    user_extension_id=$(basename $user_extension_path)
    extension_symlink_path="$MW_HOME/extensions/$user_extension_id"
    if [[ -e "$extension_symlink_path" ]]
    then
      rm "$extension_symlink_path"
    fi
    ln -s $MW_HOME/user-extensions/$user_extension_id/ $MW_HOME/extensions/$user_extension_id
  done
  echo "Symlinking user skins and overwriting any redundant bundled skins..."
  for user_skin_path in $(find $MW_HOME/user-skins/ -maxdepth 1 -mindepth 1 -type d)
  do
    user_skin_id=$(basename $user_skin_path)
    skin_symlink_path="$MW_HOME/skins/$user_skin_id"
    if [[ -e "$skin_symlink_path" ]]
    then
      rm "$skin_symlink_path"
    fi
    ln -s $MW_HOME/user-skins/$user_skin_id/ $MW_HOME/skins/$user_skin_id
  done
}

# Symlink all extensions and skins (both bundled and user)
prepare_extensions_skins_symlinks

# Soft sync contents from $MW_ORIGIN_FILES directory to $MW_VOLUME
# The goal of this operation is to copy over all the files generated
# by the image to bind-mount points on host which are bind to
# $MW_VOLUME (./extensions, ./skins, ./config, ./images),
# note that this command will also set all the necessary permissions
echo "Syncing files..."
rsync -ah --inplace --ignore-existing --remove-source-files \
  -og --chown=$WWW_GROUP:$WWW_USER --chmod=Fg=rw,Dg=rwx \
  "$MW_ORIGIN_FILES"/ "$MW_VOLUME"/

# We don't need it anymore
rm -rf "$MW_ORIGIN_FILES"

/update-docker-gateway.sh

# Permissions
# Note: this part if checking for root directories permissions
# assuming that if the root directory has correct permissions set
# it's in result of previous success run of this code or this code
# was executed by another container (in case mount points are shared)
# hence it does not perform any recursive checks and may lead to files
# or directories down the tree having incorrect permissions left untouched

echo "Checking permissions of $MW_VOLUME..."
if dir_is_writable $MW_VOLUME; then
  echo "Permissions are OK!"
else
  chown -R "$WWW_GROUP":"$WWW_GROUP" "$MW_VOLUME"
  chmod -R g=rwX "$MW_VOLUME"
fi

echo "Checking permissions of $APACHE_LOG_DIR..."
if dir_is_writable $APACHE_LOG_DIR; then
  echo "Permissions are OK!"
else
  chown -R "$WWW_GROUP":"$WWW_GROUP" $APACHE_LOG_DIR
  chmod -R g=rwX $APACHE_LOG_DIR
fi

jobrunner() {
    sleep 3
    if isTrue "$MW_ENABLE_JOB_RUNNER"; then
        echo >&2 Run Jobs
        nice -n 20 runuser -c /mwjobrunner.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Job runner is disabled
    fi
}

transcoder() {
    sleep 3
    if isTrue "$MW_ENABLE_TRANSCODER"; then
        echo >&2 Run transcoder
        nice -n 20 runuser -c /mwtranscoder.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Transcoder disabled
    fi
}

sitemapgen() {
    sleep 3
    if isTrue "$MW_ENABLE_SITEMAP_GENERATOR"; then
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
  if isFalse "$USE_EXTERNAL_DB"; then
    /wait-for-it.sh -t 60 db:3306
  fi
}

#waitelastic() {
#  ./wait-for-it.sh -t 60 elasticsearch:9200
#}

run_autoupdate () {
    echo "Running auto-update..."
    runuser -c "php maintenance/update.php --quick" -s /bin/bash "$WWW_USER"
    echo "Auto-update completed"
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

# Wait db
waitdatabase

# Check for `user-` prefixed mounts and bow out if not found
check_mount_points

sleep 1
cd "$MW_HOME" || exit

########## Run maintenance scripts ##########
echo "Checking for LocalSettings..."
if [ -e "$MW_VOLUME/config/LocalSettings.php"  ]; then
  # Run auto-update
  run_autoupdate
fi

echo "Starting services..."
jobrunner &
transcoder &
sitemapgen &

############### Run Apache ###############
# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/httpd/* /tmp/httpd*

exec /usr/sbin/apachectl -DFOREGROUND
