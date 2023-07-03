#!/bin/bash

set -x

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

# Symlink all extensions and skins (both bundled and user)
/create-symlinks.sh

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

run_maintenance_scripts() {
  # Iterate through all the .sh files in /maintenance-scripts/ directory
  for maintenance_script in $(find /maintenance-scripts/ -maxdepth 1 -mindepth 1 -type f -name "*.sh"); do
    script_name=$(basename "$maintenance_script")

    # If the script's name starts with "mw_", run it with the run_mw_script function
    if [[ "$script_name" == mw* ]]; then
      run_mw_script "$script_name" &
    else
      # If the script's name doesn't start with "mw"
      echo "Running $script_name with user $WWW_USER..."
      nice -n 20 runuser -c "/maintenance-scripts/$script_name" -s /bin/bash "$WWW_USER" &
    fi
  done
}

# Naming convention:
# Scripts with names starting with "mw_" have corresponding enable variables.
# The enable variable is formed by converting the script's name to uppercase and replacing the first underscore with "_ENABLE_". 
# For example, the enable variable for "mw_sitemap_generator.sh" would be "MW_ENABLE_SITEMAP_GENERATOR".

run_mw_script() {
  sleep 3

  # Process the script name and create the corresponding enable variable
  local script_name="$1"
  script_name_no_ext="${script_name%.*}"
  script_name_upper=$(basename "$script_name_no_ext" | tr '[:lower:]' '[:upper:]')
  local MW_ENABLE_VAR="${script_name_upper/_/_ENABLE_}"

  if isTrue "${!MW_ENABLE_VAR}"; then
    echo "Running $script_name with user $WWW_USER..."
    nice -n 20 runuser -c "/maintenance-scripts/$script_name" -s /bin/bash "$WWW_USER"
  else
    echo >&2 "$script_name is disabled."
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

inotifywait() {
	/monitor-directories.sh
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

run_maintenance_scripts &

# Running php-fpm
/run-php-fpm.sh &

############### Run Apache ###############
# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/apache2/* /tmp/apache2*

exec /usr/sbin/apachectl -DFOREGROUND
