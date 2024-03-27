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

get_hostname_with_port () {
    port=$(echo "$1" | grep ":" | cut -d":" -f2)
    echo "$1:${port:-$2}"
}

make_dir_writable() {
    find "$@" '(' -type f -o -type d ')' \
       -not '(' '(' -user "$WWW_USER" -perm -u=w ')' -o \
           '(' -group "$WWW_GROUP" -perm -g=w ')' -o \
           '(' -perm -o=w ')' \
         ')' \
         -exec chgrp "$WWW_GROUP" {} \; -exec chmod g=rwX {} \;
}
