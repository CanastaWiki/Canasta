#!/bin/bash

# Parse the YAML file and get wiki ids
wiki_ids=$(awk -F': ' '/id: .*/ {print $2}' $MW_VOLUME/config/wikis.yaml)

# Read the ids into an array
readarray -t ids <<< "$wiki_ids"

# Loop through the ids
for db_name in "${ids[@]}"; do
    # Create the cache and images directories if they don't exist
    mkdir -p $MW_VOLUME/cache/$db_name
    mkdir -p $MW_VOLUME/images/$db_name

    # Change the permissions of these directories
    chown -R $WWW_USER:$WWW_GROUP $MW_VOLUME/cache/$db_name
    chown -R $WWW_USER:$WWW_GROUP $MW_VOLUME/images/$db_name
done

# Protect Images Directory from Internet Access
echo "Deny from All" >> $MW_VOLUME/images/.htaccess 
