# read variables from LocalSettings.php
get_mediawiki_variable() {
    php /getMediawikiSettings.php --variable="$1" --format="${2:-string}"
}

get_docker_gateway () {
  getent hosts "gateway.docker.internal" | awk '{ print $1 }'
}

get_mediawiki_db_var() {
    case $1 in
        "wgDBtype")
            I="type"
            ;;
        "wgDBserver")
            I="host"
            ;;
        "wgDBname")
            I="dbname"
            ;;
        "wgDBuser")
            I="user"
            ;;
        "wgDBpassword")
            I="password"
            ;;
        *)
            echo "Unexpected variable name passed to the get_mediawiki_db_var() function: $1"
            return
    esac
    VALUE=$(php /getMediawikiSettings.php --variable=wgDBservers --variableArrayIndex="[0,\"$I\"]" --format=string)
    if [ -z "$VALUE" ]; then
        VALUE=$(get_mediawiki_variable "$1")
    fi
    echo "$VALUE"
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

get_hostname_with_port() {
    port=$(echo "$1" | grep ":" | cut -d":" -f2)
    echo "$1:${port:-$2}"
}
get_mediawiki_cirrus_search_server() {
    server=$(get_mediawiki_variable wgCirrusSearchServers first)
    if [ -z "$server" ]; then
        server=$(php /getMediawikiSettings.php --variable=wgCirrusSearchClusters --variableArrayIndex="[\"default\",0]" --format=string)
    fi
    get_hostname_with_port "$server" 9200
}

make_dir_writable() {
    find "$@" '(' -type f -o -type d ')' \
       -not '(' '(' -user "$WWW_USER" -perm -u=w ')' -o \
           '(' -group "$WWW_GROUP" -perm -g=w ')' -o \
           '(' -perm -o=w ')' \
         ')' \
         -exec chgrp "$WWW_GROUP" {} \; -exec chmod g=rwX {} \;
}

calculate_php_error_reporting() {
  php -r "error_reporting($1); echo error_reporting();"
}
