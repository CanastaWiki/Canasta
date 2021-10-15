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

autoinclude() {
  echo "Auto-include started.."
  while true; do
    # Look for LocalSettings presence
    if [ -e "$MW_VOLUME/config/LocalSettings.php"  ]; then
      # Automatically include CanastaUtils.php
      if ! grep -q "CanastaUtils.php" "$MW_VOLUME/config/LocalSettings.php"; then
        echo "Adding CanastaUtils.."
        # Add include
        sed -i 's/# End of automatically generated settings./@include("CanastaUtils.php");/g' "$MW_VOLUME/config/LocalSettings.php"
        # Replace possible load calls, though we don't expect any because the initial state of the
        # ./extensions folder should be empty so the wizard won't allow to select any skins or extensions
        # to be enabled during LocalSettings generation
        sed -i 's/wfLoadExtension/cfLoadExtension/g' "$MW_VOLUME/config/LocalSettings.php"
        sed -i 's/wfLoadSkin/cfLoadSkin/g' "$MW_VOLUME/config/LocalSettings.php"
        # Add list of bundled extensions
        echo "# List of bundled extensions" >> "$MW_VOLUME/config/LocalSettings.php"
        echo "" >> "$MW_VOLUME/config/LocalSettings.php"
        cat "$MW_VOLUME/installedExtensions.txt" >> "$MW_VOLUME/config/LocalSettings.php"
        echo "" >> "$MW_VOLUME/config/LocalSettings.php"
        # Add list of bundled skins
        echo "# List of bundled skins" >> "$MW_VOLUME/config/LocalSettings.php"
        echo "" >> "$MW_VOLUME/config/LocalSettings.php"
        cat "$MW_VOLUME/installedSkins.txt" >> "$MW_VOLUME/config/LocalSettings.php"
        # Done
        echo "Auto-include DONE"
        # Run auto-update to avoid the need to retart the stack
        run_autoupdate
        break
      else
        # Inclusion is already in place
        echo "Auto-include not needed"
        break
      fi
    fi
    sleep 1
  done
}

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
          MW_SCRIPT_PATH="w"
        fi
        export MW_SCRIPT_PATH
        echo >&2 Run sitemap generator
        nice -n 20 runuser -c /mwsitemapgen.sh -s /bin/bash "$WWW_USER"
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

# Wait db
waitdatabase

autoinclude &
# Let it cycle at least once
sleep 1

cd "$MW_HOME" || exit

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
