#!/bin/bash

RJ=$MW_HOME/maintenance/runJobs.php
logfileName=mwtranscoder_log

echo "Starting transcoder (in 180 seconds)..."

# Wait three minutes after the server starts up to give other processes time to get started
sleep 180

if [ -f "$MW_VOLUME/config/wikis.yaml" ]; then
    # Get all wiki ids from the YAML file using PHP. MediaWiki derives each
    # wiki's server and paths from wikis.yaml, given --wiki.
    wikis=$(php -r 'foreach (yaml_parse_file("'$MW_VOLUME/config/wikis.yaml'")["wikis"] as $wiki) echo $wiki["id"] . " ";')

    for wiki_id in $wikis; do
        echo "$wiki_id transcoder started."
        {
            while true; do
                logFilePrev="$logfileNow"
                logfileNow="$MW_LOG/$logfileName"_$(date +%Y%m%d)
                if [ -n "$logFilePrev" ] && [ "$logFilePrev" != "$logfileNow" ]; then
                    /rotatelogs-compress.sh "$logfileNow" "$logFilePrev" &
                fi

                date >> "$logfileNow"
                php "$RJ" --type webVideoTranscodePrioritized --maxjobs=10 --wiki="$wiki_id" >> "$logfileNow" 2>&1
                sleep 1
                php "$RJ" --type webVideoTranscode --maxjobs=1 --wiki="$wiki_id" >> "$logfileNow" 2>&1

                # Wait some seconds to let the CPU do other things, like handling web requests, etc
                echo mwtranscoder waits for "$MW_JOB_TRANSCODER_PAUSE" seconds... >> "$logfileNow"
                sleep "$MW_JOB_TRANSCODER_PAUSE"
            done
        } &
    done
else
    echo "Warning: wikis.yaml does not exist. Starting the general transcoder."
    while true; do
        php $RJ --type=webVideoTranscodePrioritized --maxjobs=10
        sleep 1
        php $RJ --type=webVideoTranscode --maxjobs=1
        # Wait some seconds to let the CPU do other things, like handling web requests, etc
        echo mwtranscoder waits for "$MW_JOB_TRANSCODER_PAUSE" seconds...
        sleep "$MW_JOB_TRANSCODER_PAUSE"
    done
fi

# Wait for all background jobs to finish
wait
