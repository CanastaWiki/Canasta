#!/bin/bash

SCRIPT=$MW_HOME/maintenance/generateSitemap.php
# Verify the delay is >= 1, otherwise fall back to 1
if [ "$MW_SITEMAP_PAUSE_DAYS" -lt "1" ]; then
    MW_SITEMAP_PAUSE_DAYS=1
fi
# Convert to seconds (suffixed sleep command has issues on OSX)
SLEEPDAYS=$(expr $MW_SITEMAP_PAUSE_DAYS \* 60 \* 60 \* 24)

echo Starting sitemap generator...
# Wait three minutes after the server starts up to give other processes time to get started
sleep 30
echo Sitemap generator started.
while true; do
    php $SCRIPT \
      --fspath=$MW_HOME/sitemap/ \
      --urlpath=w/sitemap/ \
      --compress yes \
      --server=$MW_SITE_SERVER \
      --skip-redirects \
      --identifier=mediawiki

    # Wait some seconds to let the CPU do other things, like handling web requests, etc
    echo mwsitemapgen waits for "$SLEEPDAYS" seconds...
    sleep "$SLEEPDAYS"
done
