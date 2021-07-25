#!/bin/bash
file_to_compress="${2}"
compress_exit_code=0

if [[ "${file_to_compress}" ]]; then
    # wait random number of seconds before compressing to avoid to compress log files simultaneously (especially for wiki farms)
    if [ "$LOG_FILES_COMPRESS_DELAY" -eq 0 ]; then
        DELAY=0
    else
        DELAY=$RANDOM
        ((DELAY %= "$LOG_FILES_COMPRESS_DELAY"))
    fi
    echo "Wait for $DELAY seconds before compressing ${file_to_compress}"
    sleep "$DELAY"

    if [[ -f  "${file_to_compress}" ]]; then
        echo "Compressing ${file_to_compress} ..."
        tar --gzip --create --remove-files --absolute-names --transform 's/.*\///g' --file "${file_to_compress}.tar.gz" "${file_to_compress}"

        compress_exit_code=${?}

        if [[ ${compress_exit_code} == 0 ]]; then
            echo "File ${file_to_compress} was compressed."
        else
            echo "Error compressing file ${file_to_compress} (tar exit code: ${compress_exit_code})."
        fi
    else
        echo "File ${file_to_compress} does not exist".
    fi

    # remove old log files
    if [ -n "$LOG_FILES_REMOVE_OLDER_THAN_DAYS" ] && [ "$LOG_FILES_REMOVE_OLDER_THAN_DAYS" != false ]; then
        LOG_DIRECTORY=$(dirname "${file_to_compress}")
        find "$LOG_DIRECTORY" -type f -mtime "+$LOG_FILES_REMOVE_OLDER_THAN_DAYS" ! -iname ".*" ! -iname "*.current" -exec rm -f {} \;
    fi

    # compress uncompressed old log files
    find "$LOG_DIRECTORY" -type f -mtime "+2" ! -iname ".*" ! -iname "*.current" ! -iname "*.gz" ! -iname "*.zip" -exec tar --gzip --create --remove-files --absolute-names --transform 's/.*\///g' --file {}.tar.gz {} \;
fi

exit ${compress_exit_code}
