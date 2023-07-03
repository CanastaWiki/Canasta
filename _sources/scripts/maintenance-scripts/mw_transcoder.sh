#!/bin/bash

RJ=$MW_HOME/maintenance/runJobs.php
echo Starting transcoder...
# Wait three minutes after the server starts up to give other processes time to get started
sleep 180
echo Transcoder started.
while true; do
    php $RJ --type webVideoTranscodePrioritized --maxjobs=10
    sleep 1
    php $RJ --type webVideoTranscode --maxjobs=1

    # Wait some seconds to let the CPU do other things, like handling web requests, etc
    echo mwtranscoder waits for "$MW_JOB_TRANSCODER_PAUSE" seconds...
    sleep "$MW_JOB_TRANSCODER_PAUSE"
done
