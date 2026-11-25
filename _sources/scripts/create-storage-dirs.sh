#!/bin/bash

. /functions.sh

while IFS= read -r db_name; do
    [ -n "$db_name" ] || continue

    # Create the cache, images, and public_assets directories if they don't exist
    mkdir -p "$MW_VOLUME/cache/$db_name"
    mkdir -p "$MW_VOLUME/images/$db_name"
    mkdir -p "$MW_VOLUME/public_assets/$db_name"

    # Only the directories themselves: make_dir_writable fixes their
    # contents in the background after Apache starts.
    chown "$WWW_USER:$WWW_GROUP" "$MW_VOLUME/cache/$db_name"
    chown "$WWW_USER:$WWW_GROUP" "$MW_VOLUME/images/$db_name"
    chown "$(stat -c '%u' "$MW_VOLUME/public_assets"):$WWW_GROUP" "$MW_VOLUME/public_assets/$db_name"
done <<< "$(get_wiki_ids)"

# Protect Images Directory from Internet Access (only add the rule once; this
# script runs on every container start)
htaccess="$MW_VOLUME/images/.htaccess"
if ! grep -qxF "Deny from All" "$htaccess" 2>/dev/null; then
    echo "Deny from All" >> "$htaccess"
fi
