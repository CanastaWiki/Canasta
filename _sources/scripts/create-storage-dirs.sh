#!/bin/bash

# Parse the YAML file and get wiki ids
wiki_ids=$(awk -F': ' '/id: .*/ {print $2}' $MW_VOLUME/config/wikis.yaml)

# Read the ids into an array
readarray -t ids <<< "$wiki_ids"

# Loop through the ids
for db_name in "${ids[@]}"; do
    # Create the cache, images, and public_assets directories if they don't exist
    mkdir -p $MW_VOLUME/cache/$db_name
    mkdir -p $MW_VOLUME/images/$db_name
    mkdir -p $MW_VOLUME/public_assets/$db_name

    # Change the permissions of these directories
    chown -R $WWW_USER:$WWW_GROUP $MW_VOLUME/cache/$db_name
    chown -R $WWW_USER:$WWW_GROUP $MW_VOLUME/images/$db_name
    chown $(stat -c '%u' $MW_VOLUME/public_assets):$WWW_GROUP $MW_VOLUME/public_assets/$db_name
done

# Protect Images Directory from Internet Access (only add the rule once; this
# script runs on every container start)
htaccess="$MW_VOLUME/images/.htaccess"
if ! grep -qxF "Deny from All" "$htaccess" 2>/dev/null; then
    echo "Deny from All" >> "$htaccess"
fi
