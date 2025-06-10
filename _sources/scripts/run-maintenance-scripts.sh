#!/bin/bash

sleep 0.02
printf "\n\n===== run-maintenance-scripts.sh =====\n\n\n"

set -x

. /functions.sh

WG_DB_TYPE=$(get_mediawiki_db_var wgDBtype)
WG_DB_SERVER=$(get_mediawiki_db_var wgDBserver)
WG_DB_NAME=$(get_mediawiki_db_var wgDBname)
WG_DB_USER=$(get_mediawiki_db_var wgDBuser)
WG_DB_PASSWORD=$(get_mediawiki_db_var wgDBpassword)
WG_SQLITE_DATA_DIR=$(get_mediawiki_variable wgSQLiteDataDir)
WG_SEARCH_TYPE=$(get_mediawiki_variable wgSearchType)
VERSION_HASH=$(php /getMediawikiSettings.php --versions --format=md5)

waitdatabase() {
    if [ -n "$db_started" ]; then
        return 0; # already started
    fi

    if [ "$WG_DB_TYPE" = "sqlite" ]; then
        echo >&2 "SQLite database used"
        db_started="3"
        return 0
    fi

    if [ "$WG_DB_TYPE" != "mysql" ]; then
        echo >&2 "Unsupported database type ($WG_DB_TYPE)"
        rm "$WWW_ROOT/.maintenance"
        exit 123
    fi

    if isFalse "$USE_EXTERNAL_DB"; then
      echo >&2 "Waiting for database to start"
      /wait-for-it.sh -t 86400 "$WG_DB_SERVER"
  
      mysql=( mysql -h "$WG_DB_SERVER" -u"$WG_DB_USER" -p"$WG_DB_PASSWORD" )
  
      for i in {60..0}; do
          if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
              db_started="1"
              break
          fi
          echo >&2 'Waiting for database to start...'
          sleep 1
      done
      if [ "$i" = 0 ]; then
          echo >&2 'Could not connect to the database.'
          return 1
      fi
      echo >&2 'Successfully connected to the database.'
      return 0
    fi
}

get_tables_count() {
    waitdatabase || {
        return $?
    }

    if [ "3" = "$db_started" ]; then
        # sqlite
        find "$WG_SQLITE_DATA_DIR" -type f | wc -l
        return 0
    elif [ "1" = "$db_started" ]; then
        db_user="$WG_DB_USER"
        db_password="$WG_DB_PASSWORD"
    else
        db_user="$MW_DB_INSTALLDB_USER"
        db_password="$MW_DB_INSTALLDB_PASS"
    fi
    mysql -h "$WG_DB_SERVER" -u"$db_user" -p"$db_password" -e "SELECT count(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '$WG_DB_NAME'" | sed -n 2p
}

run_maintenance_script_if_needed () {
    if [ -f "$MW_VOLUME/$1.info" ]; then
        update_info="$(cat "$MW_VOLUME/$1.info" 2>/dev/null)"
    else
        update_info=""
    fi

    if [[ "$update_info" != "$2" && -n "$2" || "$2" == "always" ]]; then
        waitdatabase || {
            return $?
        }

        i=3
        while [ -n "${!i}" ]
        do
            if [ ! -f "$(echo "${!i}" | awk '{print $1}')" ]; then
                echo >&2 "Maintenance script does not exist: ${!i}"
                return 0;
            fi
            echo >&2 "Run maintenance script: ${!i}"
            runuser -c "php ${!i}" -s /bin/bash "$WWW_USER" || {
                echo >&2 "An error occurred when the maintenance script ${!i} was running"
                return $?
            }
            i=$((i+1))
        done

        echo >&2 "Successful updated: $2"
        echo "$2" > "$MW_VOLUME/$1.info"
    else
        echo >&2 "$1 is up to date: $2."
    fi
}

run_autoupdate () {
    echo >&2 'Check for the need to run maintenance scripts'
    ### maintenance/update.php
    run_maintenance_script_if_needed 'maintenance_update' "$MW_VERSION-$MW_CORE_VERSION-$MW_MAINTENANCE_UPDATE-$VERSION_HASH" \
        'maintenance/update.php --quick' || {
            echo >&2 "An error occurred when auto-update script was running"
            return $?
        }

    echo >&2 "Auto-update completed"
}

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

########## Run maintenance scripts ##########
echo "Checking for LocalSettings..."
if [ -e "$MW_VOLUME/config/LocalSettings.php" ] || [ -e "$MW_VOLUME/config/CommonSettings.php" ]; then
  if isTrue "$MW_AUTOUPDATE"; then
      waitdatabase
      rm "$WWW_ROOT/.maintenance"
      run_autoupdate
  else
      rm "$WWW_ROOT/.maintenance"
      echo "Auto update script is disabled, MW_AUTOUPDATE is $MW_AUTOUPDATE";
  fi
  run_maintenance_scripts
else
    rm "$WWW_ROOT/.maintenance"
    set +x
    echo "There is no LocalSettings.php/CommonSettings.php file"
    n=6
    while [ ! -e "$MW_VOLUME/config/LocalSettings.php" ] && [ ! -e "$MW_VOLUME/config/CommonSettings.php" ]; do
        echo -n "#"
        if [ $n -eq 0 ]; then
            echo " There is no LocalSettings.php/CommonSettings.php file..."
            n=6
        else
            ((n--))
        fi
        sleep 10
    done

    echo
    echo "Found LocalSettings.php/CommonSettings.php file"
    set -x
    # reload variables
    WG_DB_TYPE=$(get_mediawiki_db_var wgDBtype)
    WG_DB_SERVER=$(get_mediawiki_db_var wgDBserver)
    WG_DB_NAME=$(get_mediawiki_db_var wgDBname)
    WG_DB_USER=$(get_mediawiki_db_var wgDBuser)
    WG_DB_PASSWORD=$(get_mediawiki_db_var wgDBpassword)
    WG_SQLITE_DATA_DIR=$(get_mediawiki_variable wgSQLiteDataDir)
    WG_SEARCH_TYPE=$(get_mediawiki_variable wgSearchType)
    VERSION_HASH=$(php /getMediawikiSettings.php --versions --format=md5)

    run_maintenance_scripts
fi

sleep 4
printf "\n\n>>>>> run-maintenance-scripts.sh <<<<<\n\n\n"
