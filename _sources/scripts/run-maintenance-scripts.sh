#!/bin/bash

sleep 0.02
printf "\n\n===== run-maintenance-scripts.sh =====\n\n\n"

set -x

. /functions.sh

# `set -x` echoes every expanded command, which would print the DB password to
# the container logs. Suppress tracing around any command that reads or uses it.
hide_secrets() { case "$-" in *x*) _trace_on=1; { set +x; } 2>/dev/null;; *) _trace_on=;; esac; }
show_secrets() { [ -n "$_trace_on" ] && set -x; return 0; }

hide_secrets
WG_DB_TYPE=$(get_mediawiki_db_var wgDBtype)
WG_DB_SERVER=$(get_mediawiki_db_var wgDBserver)
WG_DB_NAME=$(get_mediawiki_db_var wgDBname)
WG_DB_USER=$(get_mediawiki_db_var wgDBuser)
WG_DB_PASSWORD=$(get_mediawiki_db_var wgDBpassword)
show_secrets
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
        if [ -z "$WG_DB_TYPE" ] && isTrue "$USE_EXTERNAL_DB"; then
            echo >&2 "LocalSettings.php not yet generated — install.php may still be running. Retrying..."
            for i in {1..31}; do
                sleep 2
                WG_DB_TYPE=$(get_mediawiki_db_var wgDBtype)
                if [ "$WG_DB_TYPE" = "mysql" ]; then
                    echo >&2 "Database type detected after ${i} attempt(s)."
                    # LocalSettings.php now exists; the DB vars snapshotted at
                    # script start were empty, so reload the rest to match.
                    hide_secrets
                    WG_DB_SERVER=$(get_mediawiki_db_var wgDBserver)
                    WG_DB_NAME=$(get_mediawiki_db_var wgDBname)
                    WG_DB_USER=$(get_mediawiki_db_var wgDBuser)
                    WG_DB_PASSWORD=$(get_mediawiki_db_var wgDBpassword)
                    show_secrets
                    break
                fi
                echo >&2 "Waiting for LocalSettings.php (attempt $i/31)..."
            done
        fi
        if [ "$WG_DB_TYPE" != "mysql" ]; then
            echo >&2 "Unsupported database type ($WG_DB_TYPE)"
            rm "$WWW_ROOT/.maintenance"
            exit 123
        fi
    fi

    if isFalse "$USE_EXTERNAL_DB"; then
      echo >&2 "Waiting for database to start"
      if [[ "$WG_DB_SERVER" == *:* ]]; then
       DB_SERVER_WITH_PORT="$WG_DB_SERVER"
      else
        DB_SERVER_WITH_PORT="$WG_DB_SERVER:${MYSQL_PORT:-3306}"
      fi
      /wait-for-it.sh -t 86400 "$DB_SERVER_WITH_PORT"
  
      hide_secrets
      mysql=( mysql -h "$WG_DB_SERVER" -u"$WG_DB_USER" -p"$WG_DB_PASSWORD" )

      for i in {60..0}; do
          if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
              db_started="1"
              break
          fi
          echo >&2 'Waiting for database to start...'
          sleep 1
      done
      show_secrets
      if [ "$i" = 0 ]; then
          echo >&2 'Could not connect to the database.'
          return 1
      fi
      echo >&2 'Successfully connected to the database.'
      return 0
    fi
}

# Succeeds only when the server reports that the wiki's database does not
# exist. Any other outcome, including a failed lookup or connection, lets the
# update run.
wiki_database_missing() {
    local db_name db_host db_port output status
    [ "$WG_DB_TYPE" = "mysql" ] || return 1
    db_name=$(php /getMediawikiSettings.php --variable=wgDBname --wiki="$1") || return 1
    [ -n "$db_name" ] || return 1
    db_host="$WG_DB_SERVER"
    db_port="${MYSQL_PORT:-3306}"
    if [[ "$db_host" == *:* ]]; then
        db_port="${db_host##*:}"
        db_host="${db_host%:*}"
    fi
    hide_secrets
    output=$(mysql -h "$db_host" -P "$db_port" -u"$WG_DB_USER" -p"$WG_DB_PASSWORD" -e 'SELECT 1' "$db_name" 2>&1)
    status=$?
    show_secrets
    [ "$status" -ne 0 ] && [[ "$output" == *"ERROR 1049"* ]]
}

run_maintenance_script_if_needed () {
    local fingerprint_file="$MW_VOLUME/config/persistent/$1.info"
    if [ -f "$fingerprint_file" ]; then
        update_info="$(cat "$fingerprint_file" 2>/dev/null)"
    else
        update_info=""
    fi

    if [[ "$update_info" != "$2" && -n "$2" || "$2" == "always" ]]; then
        waitdatabase || {
            return $?
        }

        if [ -n "$update_wiki_id" ] && wiki_database_missing "$update_wiki_id"; then
            echo >&2 "$update_wiki_id: database not installed yet, skipping update"
            return 0
        fi

        i=3
        while [ -n "${!i}" ]
        do
            if [ ! -f "$(echo "${!i}" | awk '{print $1}')" ]; then
                echo >&2 "Maintenance script does not exist: ${!i}"
                return 0;
            fi
            echo >&2 "Run maintenance script: ${!i}"
            runuser -c "php ${!i}" -s /bin/bash "$WWW_USER" || {
                rc=$?
                echo >&2 "An error occurred when the maintenance script ${!i} was running"
                return $rc
            }
            i=$((i+1))
        done

        echo >&2 "Successful updated: $2"
        mkdir -p "$(dirname "$fingerprint_file")"
        echo "$2" > "$fingerprint_file"
    else
        echo >&2 "$1 is up to date: $2."
    fi
}

run_autoupdate () {
    echo >&2 'Check for the need to run maintenance scripts'

    # Get all wiki IDs (if wiki farm) or use empty string for single wiki
    wiki_ids=$(get_wiki_ids)

    rc=0
    update_wiki_id=
    if [ -n "$wiki_ids" ]; then
        # Wiki farm: run update.php for each wiki
        echo >&2 "Wiki farm detected, running maintenance for all wikis..."
        while IFS= read -r wiki_id; do
            if [ -n "$wiki_id" ]; then
                echo >&2 "Running maintenance/update.php for wiki: $wiki_id"
                wiki_version_hash=$(php /getMediawikiSettings.php --versions --format=md5 --wiki="$wiki_id")
                update_wiki_id=$wiki_id
                run_maintenance_script_if_needed "maintenance_update_$wiki_id" "$MW_VERSION-$MW_CORE_VERSION-$MW_MAINTENANCE_UPDATE-$wiki_version_hash" \
                    "maintenance/update.php --quick --wiki=$wiki_id" || {
                        rc=$?
                        echo >&2 "An error occurred when auto-update script was running for wiki: $wiki_id"
                    }
            fi
        done <<< "$wiki_ids"
        update_wiki_id=
    else
        # Single wiki (legacy mode)
        run_maintenance_script_if_needed 'maintenance_update' "$MW_VERSION-$MW_CORE_VERSION-$MW_MAINTENANCE_UPDATE-$VERSION_HASH" \
            'maintenance/update.php --quick' || {
                rc=$?
                echo >&2 "An error occurred when auto-update script was running"
                return $rc
            }
    fi

    if [ "$rc" -ne 0 ]; then
        echo >&2 "Auto-update completed with errors"
        return $rc
    fi
    echo >&2 "Auto-update completed"
}

# Sessions are stored in the canasta_sessions table (CanastaDefaultSettings.php),
# so every wiki needs it whether or not update.php ran.
create_sessions_tables () {
    local wiki_ids wiki_id
    waitdatabase || return $?
    wiki_ids=$(get_wiki_ids)
    if [ -z "$wiki_ids" ]; then
        create_sessions_table ""
        return 0
    fi
    while IFS= read -r wiki_id; do
        [ -n "$wiki_id" ] && create_sessions_table "$wiki_id"
    done <<< "$wiki_ids"
    return 0
}

create_sessions_table () {
    if [ -n "$1" ] && wiki_database_missing "$1"; then
        return 0
    fi
    runuser -c "php maintenance/createSessionsTable.php${1:+ --wiki=$1}" -s /bin/bash "$WWW_USER" ||
        echo >&2 "Could not create the sessions table${1:+ for wiki: $1}"
}

run_maintenance_scripts() {
  # Iterate through all the .sh files in /maintenance-scripts/ directory
  for maintenance_script in $(find /maintenance-scripts/ -maxdepth 1 -mindepth 1 -type f -name "*.sh" | sort); do
    script_name=$(basename "$maintenance_script")

    # If the script's name starts with "mw_", run it with the run_mw_script function
    if [[ "$script_name" == mw* ]]; then
      run_mw_script "$script_name" &
    elif [[ "$script_name" == monitor-directories.sh ]]; then
      echo "Running $script_name with user $LINKS_USER..."
      nice -n 20 runuser -c "/maintenance-scripts/$script_name" -s /bin/bash "$LINKS_USER" &
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
# For example, the enable variable for "mw_job_runner.sh" would be "MW_ENABLE_JOB_RUNNER".

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
#
# This block is the script's "executable" entry point. It only fires
# when the file is run directly (e.g. `/run-maintenance-scripts.sh &`
# from run-all.sh) — NOT when the file is sourced for its helper
# functions (which run-all.sh also does, with `. /run-maintenance-scripts.sh`).
# Without this guard, sourcing the file silently triggers a full
# maintenance run as a side effect, racing the explicit invocations
# elsewhere and producing misleading DB / schema errors in the logs.
# See issue #143.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return 0
fi

# Check for valid configuration:
# - New architecture: config/wikis.yaml (wiki farm config used by FarmConfigLoader.php)
# - Legacy: config/LocalSettings.php or config/CommonSettings.php
echo "Checking for configuration..."
if [ -e "$MW_VOLUME/config/wikis.yaml" ] || [ -e "$MW_VOLUME/config/LocalSettings.php" ] || [ -e "$MW_VOLUME/config/CommonSettings.php" ]; then
  # run-all.sh has already run the auto-update before starting this script.
  if isTrue "$MW_AUTOUPDATE"; then
      waitdatabase
  fi
  rm "$WWW_ROOT/.maintenance"
  run_maintenance_scripts
else
    rm "$WWW_ROOT/.maintenance"
    set +x
    echo "Waiting for configuration (wikis.yaml or LocalSettings.php)..."
    n=6
    while [ ! -e "$MW_VOLUME/config/wikis.yaml" ] && [ ! -e "$MW_VOLUME/config/LocalSettings.php" ] && [ ! -e "$MW_VOLUME/config/CommonSettings.php" ]; do
        echo -n "#"
        if [ $n -eq 0 ]; then
            echo " Waiting for configuration..."
            n=6
        else
            ((n--))
        fi
        sleep 10
    done

    echo
    echo "Found configuration file"
    set -x
    # reload variables
    hide_secrets
    WG_DB_TYPE=$(get_mediawiki_db_var wgDBtype)
    WG_DB_SERVER=$(get_mediawiki_db_var wgDBserver)
    WG_DB_NAME=$(get_mediawiki_db_var wgDBname)
    WG_DB_USER=$(get_mediawiki_db_var wgDBuser)
    WG_DB_PASSWORD=$(get_mediawiki_db_var wgDBpassword)
    show_secrets
    VERSION_HASH=$(php /getMediawikiSettings.php --versions --format=md5)

    run_maintenance_scripts
fi

sleep 4
printf "\n\n>>>>> run-maintenance-scripts.sh <<<<<\n\n\n"
