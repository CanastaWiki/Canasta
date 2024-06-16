#!/bin/bash

RJ=$MW_HOME/maintenance/runJobs.php
logfileName=mwtranscoder_log

echo "Starting transcoder (in 180 seconds)..."

# Wait three minutes after the server starts up to give other processes time to get started
sleep 180

# Get all wiki ids and URLs from the YAML file using PHP
if [ -f "$MW_VOLUME/config/wikis.yaml" ]; then
    # Get all wiki ids and URLs from the YAML file using PHP
    wikis=$(php -r 'foreach (yaml_parse_file("'$MW_VOLUME/config/wikis.yaml'")["wikis"] as $wiki) echo $wiki["id"] . "," . $wiki["url"] . " ";')

    for wiki in $wikis; do
        # Extract wiki id and url
        IFS=', ' read -r -a wiki_data <<< "$wiki"
        wiki_id=${wiki_data[0]}
        wiki_url=${wiki_data[1]}
        echo "$wiki_id transcoder started."
        {
            while true; do
                logFilePrev="$logfileNow"
                logfileNow="$MW_LOG/$logfileName"_$(date +%Y%m%d)
                if [ -n "$logFilePrev" ] && [ "$logFilePrev" != "$logfileNow" ]; then
                    /rotatelogs-compress.sh "$logfileNow" "$logFilePrev" &
                fi

                date >> "$logfileNow"
                php "$RJ" --type webVideoTranscodePrioritized --maxjobs=10 >> "$logfileNow" 2>&1
                sleep 1
                php "$RJ" --type webVideoTranscode --maxjobs=1 >> "$logfileNow" 2>&1

                # Wait some seconds to let the CPU do other things, like handling web requests, etc
                echo mwtranscoder waits for "$MW_JOB_TRANSCODER_PAUSE" seconds... >> "$logfileNow"
                sleep "$MW_JOB_TRANSCODER_PAUSE"
            done
        } &
    done
else
    echo "Warning: wikis.yaml does not exist. Starting the general transcoder."
    php $RJ --type=webVideoTranscodePrioritized --maxjobs=10
    sleep 1
    php $RJ --type=webVideoTranscode --maxjobs=1
    # Wait some seconds to let the CPU do other things, like handling web requests, etc
    echo mwtranscoder waits for "$MW_JOB_TRANSCODER_PAUSE" seconds...
    sleep "$MW_JOB_TRANSCODER_PAUSE"
fi

# Wait for all background jobs to finish
wait
