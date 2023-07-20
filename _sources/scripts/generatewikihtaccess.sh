#!/bin/bash

# Parse the YAML file and get wiki paths
wiki_paths=$(awk -F'/' '/url: .*/ {split($2, arr, "/"); if (arr[length(arr)] != "") print arr[length(arr)]}' $MW_VOLUME/config/wikis.yaml)

# An associative array to keep track of processed paths
declare -A processed_paths

# Loop through the paths
for path in $wiki_paths; do
  if [[ -z ${processed_paths[$path]} ]]; then
    # Mark this path as processed
    processed_paths[$path]=1

    # Create directory if it doesn't exist
    mkdir -p $WWW_ROOT/$path

    # Create symbolic link to MediaWiki
    ln -sf $MW_HOME $WWW_ROOT/$path

    # Modify .htaccess file
    sed -e "s|w/rest.php/|$path/w/rest.php/|g" \
    -e "s|w/img_auth.php/|$path/w/img_auth.php/|g" \
    -e "s|^/*$ %{DOCUMENT_ROOT}/w/index.php|/*$ %{DOCUMENT_ROOT}/$path/w/index.php|" \
    -e "s|^\\(.*\\)$ %{DOCUMENT_ROOT}/w/index.php|\\1$ %{DOCUMENT_ROOT}/$path/w/index.php|" \
    $WWW_ROOT/.htaccess > $WWW_ROOT/$path/.htaccess
  fi
done
