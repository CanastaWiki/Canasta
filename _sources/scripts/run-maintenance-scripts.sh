#!/bin/bash

sleep 0.02

# Check if BOOTSTRAP_LOGFILE is defined and not empty
if [ -n "$BOOTSTRAP_LOGFILE" ]; then
    # If BOOTSTRAP_LOGFILE is defined, set up logging
    # Open file descriptor 3 for logging xtrace output
    exec 3>>"$BOOTSTRAP_LOGFILE"
    BASH_XTRACEFD=3
fi
set -x

printf "\n\n===== run-maintenance-script.sh =====\n\n\n"

. /functions.sh

# Remove LocalSettings.php file in MW_VOLUME directory if is is a broken symbolic link
# For backward compatibility, when LocalSettings.php is a broken link to /var/www/html/w/DockerSettings.php file
if [ -L "$MW_VOLUME/LocalSettings.php" ] && [ ! -e "$MW_VOLUME/LocalSettings.php" ]; then
    mv "$MW_VOLUME/LocalSettings.php" "$MW_VOLUME/ToBeDeleted-$(date +%Y%m%d-%H%M%S)-LocalSettings.php"
fi

WG_DB_TYPE=$(get_mediawiki_variable wgDBtype)
WG_DB_SERVER=$(get_mediawiki_variable wgDBserver)
WG_DB_NAME=$(get_mediawiki_variable wgDBname)
WG_DB_USER=$(get_mediawiki_variable wgDBuser)
WG_DB_PASSWORD=$(get_mediawiki_variable wgDBpassword)
WG_SQLITE_DATA_DIR=$(get_mediawiki_variable wgSQLiteDataDir)
WG_LANG_CODE=$(get_mediawiki_variable wgLanguageCode)
WG_SITE_NAME=$(get_mediawiki_variable wgSitename)
WG_SEARCH_TYPE=$(get_mediawiki_variable wgSearchType)
WG_CIRRUS_SEARCH_SERVER=$(get_hostname_with_port "$(get_mediawiki_variable wgCirrusSearchServers first)" 9200)
VERSION_HASH=$(php /getMediawikiSettings.php --versions --format=md5)
if [ -z "$MW_DB_INSTALLDB_PASS" ] && [ -f /run/secrets/db_root_password ]; then
    MW_DB_INSTALLDB_PASS=$(< /run/secrets/db_root_password)
fi

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
        exit 123
    fi

    echo >&2 "Waiting for database to start"
    /wait-for-it.sh -t 86400 "$WG_DB_SERVER:3306"

    mysql=( mysql -h "$WG_DB_SERVER" -u"$WG_DB_USER" -p"$WG_DB_PASSWORD" )
    mysql_install=( mysql -h "$WG_DB_SERVER" -u"$MW_DB_INSTALLDB_USER" -p"$MW_DB_INSTALLDB_PASS" )

    for i in {60..0}; do
        if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
            db_started="1"
            break
        fi
        sleep 1
        if echo 'SELECT 1' | "${mysql_install[@]}" &> /dev/null; then
            db_started="2"
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
}

waitelastic() {
    if [ -n "$es_started" ]; then
        return 0; # already started
    fi

    echo >&2 'Waiting for elasticsearch to start'
    /wait-for-it.sh -t 60 "$WG_CIRRUS_SEARCH_SERVER"

    for i in {300..0}; do
        result=0
        output=$(wget --timeout=1 -q -O - "http://$WG_CIRRUS_SEARCH_SERVER/_cat/health") || result=$?
        if [[ "$result" = 0 && $(echo "$output"|awk '{ print $4 }') = "green" ]]; then
            break
        fi
        if [ "$result" = 0 ]; then
            echo >&2 "Waiting for elasticsearch health status changed from [$(echo "$output"|awk '{ print $4 }')] to [green]..."
        else
            echo >&2 'Waiting for elasticsearch to start...'
        fi
        sleep 1
    done
    if [ "$i" = 0 ]; then
        echo >&2 'Elasticsearch is not ready for use'
        echo "$output"
        return 1
    fi
    echo >&2 'Elasticsearch started successfully'
    es_started="1"
    return 0
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
        if [[ "$1" == *CirrusSearch* ]]; then
            waitelastic || {
                return $?
            }
        fi

        i=3
        while [ -n "${!i}" ]
        do
            if [ ! -f "$(echo "${!i}" | awk '{print $1}')" ]; then
                echo >&2 "Maintenance script does not exit: ${!i}"
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

run_script_if_needed () {
    if [ -f "$MW_VOLUME/$1.info" ]; then
        update_info="$(cat "$MW_VOLUME/$1.info" 2>/dev/null)"
    else
        update_info=""
    fi

    if [[ "$update_info" != "$2" && -n "$2" && "${2: -1}" != '-' ]]; then
        waitdatabase || {
            return $?
        }
        if [[ "$1" == *CirrusSearch* ]]; then
            waitelastic || {
                return $?
            }
        fi
        echo >&2 "Run script: $3"
        eval "$3" || {
            echo >&2 "An error occurred when the script $3 was running"
            return $?
        }

        cd "$MW_HOME" || exit

        echo >&2 "Successful updated: $2"
        echo "$2" > "$MW_VOLUME/$1.info"
    else
        echo "$1 is skipped: $2."
    fi
}

# If there is no LocalSettings.php and $WG_DB_SERVER is defined
if [ ! -e "$MW_VOLUME/LocalSettings.php" ] && [ ! -e "$MW_HOME/LocalSettings.php" ] && [ ! -e "$MW_CONFIG_DIR/LocalSettings.php" ]; then
    echo "There is no LocalSettings.php file"

    if [ "$WG_DB_TYPE" != "sqlite" ] && [ -z "$WG_DB_SERVER" ]; then
        echo "Database server is not defined, skip installation of the wiki"
    else
        if [ "$WG_DB_TYPE" = "sqlite" ]; then
            echo "Sqlite database used"
        else
            echo "Defined database server: $WG_DB_SERVER"
        fi
        # Check that the database and table exists (docker creates an empty database)
        tables_count=$(get_tables_count)
        if [[ "$tables_count" -gt 0 ]] ; then
            echo "Database exists. Create a symlink to DockerSettings.php as LocalSettings.php"
            ln -s "$MW_HOME/DockerSettings.php" "$MW_VOLUME/LocalSettings.php"
        else
            if [ -z "$MW_ADMIN_USER" ] && [ -f /run/secrets/mw_admin_user ]; then
                MW_ADMIN_USER=$(< /run/secrets/mw_admin_user)
            fi
            if [ -z "${MW_ADMIN_PASS}" ] && [ -f /run/secrets/mw_admin_password ]; then
                MW_ADMIN_PASS=$(< /run/secrets/mw_admin_password)
            fi
            for x in MW_DB_INSTALLDB_PASS MW_ADMIN_USER MW_ADMIN_PASS
            do
                if [ -z "${!x}" ]; then
                    echo >&2 "Variable $x must be defined";
                    exit 1;
                fi
            done

            echo "Create database and LocalSettings.php using maintenance/install.php"
            php maintenance/install.php \
                --confpath "$MW_VOLUME" \
                --dbserver "$WG_DB_SERVER" \
                --dbtype "$WG_DB_TYPE" \
                --dbname "$WG_DB_NAME" \
                --dbuser "$WG_DB_USER" \
                --dbpass "$WG_DB_PASSWORD" \
                --dbpath "$WG_SQLITE_DATA_DIR" \
                --installdbuser "$MW_DB_INSTALLDB_USER" \
                --installdbpass "$MW_DB_INSTALLDB_PASS" \
                --scriptpath "/w" \
                --lang "$WG_LANG_CODE" \
                --pass "$MW_ADMIN_PASS" \
                --skins "" \
                "$WG_SITE_NAME" \
                "$MW_ADMIN_USER"

            # Check if the installation script did not end with zero exit code and
            # if so display an error and exit the process
            installExitCode=$?
            if [ $installExitCode -ne 0 ]; then
                echo "ERROR: install.php did not complete successfully, setup is aborted!"
                # To prevent immediate container restart with unless-stopped policy
                sleep 5
                exit 1
            fi

            # Append inclusion of DockerSettings.php
            echo "@include('DockerSettings.php');" >> "$MW_VOLUME/LocalSettings.php"
        fi
    fi
fi

# Create symbolic link if not exists
if [ -e "$MW_VOLUME/LocalSettings.php" ] && [ ! -e "$MW_HOME/LocalSettings.php" ]; then
    ln -s "$MW_VOLUME/LocalSettings.php" "$MW_HOME/LocalSettings.php"
fi

rm "$WWW_ROOT/.maintenance"

# Reload the settings
WG_DB_TYPE=$(get_mediawiki_variable wgDBtype)
WG_DB_SERVER=$(get_mediawiki_variable wgDBserver)
WG_DB_NAME=$(get_mediawiki_variable wgDBname)
WG_DB_USER=$(get_mediawiki_variable wgDBuser)
WG_DB_PASSWORD=$(get_mediawiki_variable wgDBpassword)
WG_SQLITE_DATA_DIR=$(get_mediawiki_variable wgSQLiteDataDir)
WG_LANG_CODE=$(get_mediawiki_variable wgLanguageCode)
WG_SITE_NAME=$(get_mediawiki_variable wgSitename)
WG_SEARCH_TYPE=$(get_mediawiki_variable wgSearchType)
WG_CIRRUS_SEARCH_SERVER=$(get_hostname_with_port "$(get_mediawiki_variable wgCirrusSearchServers first)" 9200)
VERSION_HASH=$(php /getMediawikiSettings.php --versions --format=md5)

jobrunner() {
    sleep 1
    if isTrue "$MW_ENABLE_JOB_RUNNER"; then
        echo >&2 Run Jobs
        nice -n 20 runuser -c /mwjobrunner.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Job runner is disabled
    fi
}

transcoder() {
    sleep 2
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
        echo >&2 Run sitemap generator
        nice -n 20 runuser -c /mwsitemapgen.sh -s /bin/bash "$WWW_USER"
    else
        echo >&2 Sitemap generator is disabled
    fi
}

run_autoupdate () {
    echo >&2 'Check for the need to run maintenance scripts'
    ### maintenance/update.php

#    if [ "$(php /getMediawikiSettings.php --isSMWValid)" = false ]; then
#        SMW_UPGRADE_KEY=
#        UPDATE_DATABASE_ANYWAY=true
#    else
#        UPDATE_DATABASE_ANYWAY=false
#    fi

    SMW_UPGRADE_KEY=$(php /getMediawikiSettings.php --SMWUpgradeKey)
    run_maintenance_script_if_needed 'maintenance_update' "$MW_VERSION-$MW_CORE_VERSION-$MW_MAINTENANCE_UPDATE-$VERSION_HASH-$SMW_UPGRADE_KEY" \
        'maintenance/update.php --quick' || {
            echo >&2 "An error occurred when auto-update script was running"
            return $?
        }

#    run_maintenance_script_if_needed 'maintenance_update' "always"
#        'maintenance/update.php --quick'


    # Run incomplete SemanticMediawiki setup tasks
    SMW_INCOMPLETE_TASKS=$(php /getMediawikiSettings.php --SWMIncompleteSetupTasks --format=space)
    for task in $SMW_INCOMPLETE_TASKS
    do
        case $task in
            smw-updateentitycollation-incomplete)
                run_maintenance_script_if_needed 'maintenance_semantic_updateEntityCollation' "always" \
                    'extensions/SemanticMediaWiki/maintenance/updateEntityCollation.php'
                ;;
            smw-updateentitycountmap-incomplete)
                run_maintenance_script_if_needed 'maintenance_semantic_updateEntityCountMap' "always" \
                    'extensions/SemanticMediaWiki/maintenance/updateEntityCountMap.php'
                ;;
            *)
                echo >&2 "######## Unknown SMW maintenance setup task - $task ########"
                ;;
        esac
    done

    ### CirrusSearch
    if [ "$WG_SEARCH_TYPE" == 'CirrusSearch' ]; then
        run_maintenance_script_if_needed 'maintenance_CirrusSearch_updateConfig' "${EXTRA_MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG}${MW_MAINTENANCE_CIRRUSSEARCH_UPDATECONFIG}${MW_VERSION}" \
            'extensions/CirrusSearch/maintenance/UpdateSearchIndexConfig.php --reindexAndRemoveOk --indexIdentifier now' && \
        run_maintenance_script_if_needed 'maintenance_CirrusSearch_forceIndex' "${EXTRA_MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX}${MW_MAINTENANCE_CIRRUSSEARCH_FORCEINDEX}${MW_VERSION}" \
            'extensions/CirrusSearch/maintenance/ForceSearchIndex.php --skipLinks --indexOnSkip' \
            'extensions/CirrusSearch/maintenance/ForceSearchIndex.php --skipParse'
    fi

    ### GoogleLogin
    GoogleLoginVersion=$(php /getMediawikiSettings.php --version GoogleLogin)
    # TODO ideally we should run the maintenance script if the PublicSuffixArray does not exist
    if  [ -n "$GoogleLoginVersion" ]; then
        wgGLAllowedDomainsMD5=$(get_mediawiki_variable wgGLAllowedDomains md5)
        run_maintenance_script_if_needed 'maintenance_GoogleLogin_updatePublicSuffixArray' "${GoogleLoginVersion}${wgGLAllowedDomainsMD5}" 'extensions/GoogleLogin/maintenance/updatePublicSuffixArray.php'
    fi

    echo >&2 "Auto-update completed"
}

run_import () {
    # Import PagePort dumps if any
    if [ -d "$MW_IMPORT_VOLUME" ]; then
        echo "Found $MW_IMPORT_VOLUME, running PagePort import.."
        XML_TEST=($(find $MW_IMPORT_VOLUME -maxdepth 1 -name "*.xml"))
        if [ ${#XML_TEST[@]} -gt 0 ]; then
        	echo "WARNING! The directory contains XML files, did you forget to migrate the dump to PagePort?"
        	return
        fi
        php extensions/PagePort/maintenance/importPages.php --source "$MW_IMPORT_VOLUME" --user 'Maintenance script'
        echo "Imported completed!"
    fi
}

########## Run maintenance scripts ##########
if isTrue "$MW_AUTOUPDATE"; then
    run_autoupdate
else
    echo "Auto update script is disabled, MW_AUTOUPDATE is $MW_AUTOUPDATE";
fi

# Run import after install and update are completed
if isTrue "$MW_AUTO_IMPORT"; then
	run_import
fi

jobrunner &
transcoder &
sitemapgen &

########## Run Monit ##########
if [ -n "$MONIT_SLACK_HOOK" ]; then
    echo "Starting monit.."
    monit -I -c /etc/monitrc &
else
    echo "Skip monit (MONIT_SLACK_HOOK is not defined)"
fi

# Run extra post-init scripts if any
if [ -f "/post-init.sh" ]; then
    chmod +x /post-init.sh
    echo >&2 Running post-init.sh script..
    /bin/bash /post-init.sh
fi

sleep 4
printf "\n\n>>>>> run-maintenance-script.sh <<<<<\n\n\n"
