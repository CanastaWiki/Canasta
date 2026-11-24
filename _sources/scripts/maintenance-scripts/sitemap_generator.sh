#!/bin/bash

. /functions.sh

SCRIPT=$MW_HOME/maintenance/generateSitemap.php
logfileName=mwsitemapgen_log

# Verify the delay is >= 1, otherwise fall back to 1
if [ "$MW_SITEMAP_PAUSE_DAYS" -lt "1" ]; then
    MW_SITEMAP_PAUSE_DAYS=1
fi
# Convert to seconds (suffixed sleep command has issues on OSX)
SLEEP_DAYS=$((MW_SITEMAP_PAUSE_DAYS * 60 * 60 * 24))

# Get the URL scheme from MW_SITE_SERVER (e.g. "https://")
URL_SCHEME=$(echo "$MW_SITE_SERVER" | grep -oP '^https?://')
if [ -z "$URL_SCHEME" ]; then
    URL_SCHEME="https://"
fi

# URL path of the sitemap files, relative to each wiki's URL
URL_PATH="${MW_SITEMAP_URL_PATH:-/public_assets/sitemap}"

# Generate sitemap for a single wiki
generate_sitemap_for_wiki() {
    local wiki_id="$1"
    local identifier="$2"
    local server="$3"
    local urlpath="$4"
    local log="$5"
    local fspath="$MW_HOME/public_assets/$wiki_id/sitemap"

    echo "Generating sitemap for wiki: $wiki_id (server: $server, identifier: $identifier)" >> "$log"
    if ! php "$SCRIPT" \
      --wiki="$wiki_id" \
      --fspath="$fspath" \
      --urlpath="$urlpath" \
      --compress yes \
      --server="$server" \
      --skip-redirects \
      --identifier="$identifier" \
      >> "$log" 2>&1; then
        return
    fi

    # Remove the index and sitemaps of any earlier identifier, so the
    # combined /sitemap.xml lists only the current one
    local file name
    for file in "$fspath"/sitemap-*; do
        [ -e "$file" ] || continue
        name="${file##*/}"
        case "$name" in
            "sitemap-index-$identifier.xml" | "sitemap-$identifier-NS_"*) ;;
            sitemap-index-*.xml | sitemap-*-NS_*) rm -f "$file" ;;
        esac
    done
}

echo "Starting sitemap generator (in 30 seconds)..."
# Wait after the server starts up to give other processes time to get started
sleep 30
echo "Sitemap generator started."
while true; do
    logFilePrev="$logfileNow"
    logfileNow="$MW_LOG/$logfileName"_$(date +%Y%m%d)
    if [ -n "$logFilePrev" ] && [ "$logFilePrev" != "$logfileNow" ]; then
        /rotatelogs-compress.sh "$logfileNow" "$logFilePrev" &
    fi

    date >> "$logfileNow"

    # Get wiki IDs and URLs from wikis.yaml
    WIKIS_YAML="$MW_VOLUME/config/wikis.yaml"
    if [ ! -f "$WIKIS_YAML" ]; then
        echo "wikis.yaml not found, skipping." >> "$logfileNow"
        echo "mwsitemapgen waits for $SLEEP_DAYS seconds..." >> "$logfileNow"
        sleep "$SLEEP_DAYS"
        continue
    fi

    # Regenerate sitemaps for wikis that already have sitemap files.
    # The identifier, which names the sitemap files, defaults to the wiki
    # ID; it becomes part of file names, so other characters are refused.
    wiki_data=$(php -r "
        \$config = yaml_parse_file('$WIKIS_YAML');
        if (\$config && isset(\$config['wikis'])) {
            foreach (\$config['wikis'] as \$wiki) {
                \$id = \$wiki['id'] ?? '';
                \$url = \$wiki['url'] ?? '';
                \$identifier = (string)(\$wiki['sitemap_identifier'] ?? \$id);
                \$dir = '$MW_HOME/public_assets/' . \$id . '/sitemap';
                if (\$id !== '' && is_dir(\$dir) && count(glob(\$dir . '/*')) > 0) {
                    if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9_.-]*\$/', \$identifier)) {
                        fwrite(STDERR, 'Skipping wiki ' . \$id . ': sitemap_identifier may contain only letters, digits, underscores, hyphens and periods, and must start with a letter or digit.' . PHP_EOL);
                        continue;
                    }
                    echo \$id . \"\t\" . \$identifier . \"\t\" . \$url . \"\n\";
                }
            }
        }
    " 2>> "$logfileNow")
    if [ -z "$wiki_data" ]; then
        echo "No wikis have sitemaps, skipping." >> "$logfileNow"
    fi
    while IFS=$'\t' read -r wiki_id identifier wiki_url; do
        if [ -z "$wiki_id" ]; then
            continue
        fi
        # The server is the scheme and host only; page URLs already carry
        # the wiki's path, and the index's links to its sitemaps get it here
        wiki_path=""
        if [ -n "$wiki_url" ]; then
            server="${URL_SCHEME}${wiki_url%%/*}"
            if [[ "$wiki_url" == */* ]]; then
                wiki_path="/${wiki_url#*/}"
            fi
        else
            server="$MW_SITE_SERVER"
        fi
        generate_sitemap_for_wiki "$wiki_id" "$identifier" "$server" \
            "${wiki_path}${URL_PATH}" "$logfileNow"
    done <<< "$wiki_data"

    echo "mwsitemapgen waits for $SLEEP_DAYS seconds..." >> "$logfileNow"
    sleep "$SLEEP_DAYS"
done
