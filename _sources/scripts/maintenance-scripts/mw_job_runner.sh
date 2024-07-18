#!/bin/bash

RJ=$MW_HOME/maintenance/runJobs.php
logfileName=mwjobrunner_log

echo "Starting job runner (in 10 seconds)..."

# Wait 10 seconds after the server starts up to give other processes time to get started
sleep 10

# Check if wikis.yaml file exists
if [ -f "$MW_VOLUME/config/wikis.yaml" ]; then
    # Get all wiki ids and URLs from the YAML file using PHP
    wikis=$(php -r '$wikis = yaml_parse_file("'$MW_VOLUME/config/wikis.yaml'")["wikis"]; foreach ($wikis as $wiki) { echo $wiki["id"] . "," . $wiki["url"] . " "; }')

    for wiki_data in $wikis; do
        # Split the id and url data into separate variables
        IFS=',' read -r wiki_id wiki_url <<< "$wiki_data"
        
        echo "$wiki_id job runner started"

        {
            while true; do
                logFilePrev="$logfileNow"
                logfileNow="$MW_LOG/$logfileName"_$(date +%Y%m%d)
                if [ -n "$logFilePrev" ] && [ "$logFilePrev" != "$logfileNow" ]; then
                    /rotatelogs-compress.sh "$logfileNow" "$logFilePrev" &
                fi

                date >> "$logfileNow"
                # Job types that need to be run ASAP no matter how many of them are in the queue
                # Those jobs should be very "cheap" to run
                php $RJ --memory-limit="$MW_JOB_RUNNER_MEMORY_LIMIT" --type="enotifNotify" --server="https://$wiki_url" --wiki="$wiki_id" >> "$logfileNow" 2>&1
                sleep 1
                php $RJ --memory-limit="$MW_JOB_RUNNER_MEMORY_LIMIT" --type="createPage" --server="https://$wiki_url" --wiki="$wiki_id" >> "$logfileNow" 2>&1
                sleep 1
                php $RJ --memory-limit="$MW_JOB_RUNNER_MEMORY_LIMIT" --type="refreshLinks" --server="https://$wiki_url" --wiki="$wiki_id" >> "$logfileNow" 2>&1
                sleep 1
                php $RJ --memory-limit="$MW_JOB_RUNNER_MEMORY_LIMIT" --type="htmlCacheUpdate" --maxjobs=500 --server="https://$wiki_url" --wiki="$wiki_id" >> "$logfileNow" 2>&1
                sleep 1
                # Everything else, limit the number of jobs on each batch
                # The --wait parameter will pause the execution here until new jobs are added,
                # to avoid running the loop without anything to do
                php $RJ --maxjobs=10 --server="https://$wiki_url" --wiki="$wiki_id" >> "$logfileNow" 2>&1

                # Wait some seconds to let the CPU do other things, like handling web requests, etc
                echo mwjobrunner waits for "$MW_JOB_RUNNER_PAUSE" seconds... >> "$logfileNow"
                sleep "$MW_JOB_RUNNER_PAUSE"
            done
        } &
    done
else
    # wikis.yaml file does not exist. Skip parsing and running specific wiki jobs.
    echo "Warning: wikis.yaml does not exist. Running general jobs."
    
    # Place your general (non-wiki-specific) job run commands here.
    php $RJ --type="enotifNotify"
    sleep 1
    php $RJ --type="createPage"
    sleep 1
    php $RJ --type="refreshLinks"
    sleep 1
    php $RJ --type="htmlCacheUpdate" --maxjobs=500
    sleep 1
    php $RJ --maxjobs=10
fi

# Wait for all background jobs to finish
wait
