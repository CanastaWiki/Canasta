#!/bin/bash

# Rotates MediaWiki log files in $MW_LOG daily.
# Uses copy+truncate so PHP keeps writing to the same inode.
# Old rotated files are compressed and cleaned up by rotatelogs-compress.sh,
# which honors LOG_FILES_COMPRESS_DELAY and LOG_FILES_REMOVE_OLDER_THAN_DAYS.

logfileName=mwlogrotator_log

echo "Starting MediaWiki log rotator..."

while true; do
    logFilePrev="$logfileNow"
    logfileNow="$MW_LOG/$logfileName"_$(date +%Y%m%d)
    if [ -n "$logFilePrev" ] && [ "$logFilePrev" != "$logfileNow" ]; then
        /rotatelogs-compress.sh "$logfileNow" "$logFilePrev" &
    fi

    today=$(date +%Y%m%d)
    for logfile in "$MW_LOG"/*.log; do
        [ -f "$logfile" ] || continue
        base=$(basename "$logfile" .log)
        rotated="${MW_LOG}/${base}_log_${today}"
        if [ -s "$logfile" ]; then
            cp "$logfile" "$rotated"
            truncate -s 0 "$logfile"
            echo "$(date): Rotated $logfile -> $rotated" >> "$logfileNow"
            /rotatelogs-compress.sh "$logfileNow" "$rotated" &
        fi
    done

    # Sleep until tomorrow
    sleep 86400
done
