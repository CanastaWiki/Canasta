#!/bin/bash
# Enable extended globbing for +([0-9]) pattern.
shopt -s extglob

# Returns common prefix of two strings
common_prefix() {
  local n=0
  # Compare strings char-by-char and stop at first mismatch/end.
  while [[ -n "${1:n:1}" && "${1:n:1}" == "${2:n:1}" ]]; do
    ((n++))
  done
  echo "${1:0:n}"
}

new_log_file="${1}"
file_to_compress="${2}"
commonFilePrefix=""
if [ -n "$new_log_file" ] && [ -n "$file_to_compress" ] && [ "$new_log_file" != "$file_to_compress" ]; then
    new_log_file_basename=$(basename -- "$new_log_file")
    file_to_compress_basename=$(basename -- "$file_to_compress")
    commonFilePrefix=$(common_prefix "$new_log_file_basename" "$file_to_compress_basename")
    # Trim trailing digits
    commonFilePrefix="${commonFilePrefix%%+([0-9])}"
fi

# Fallback: derive prefix from file_to_compress basename to avoid empty prefix ("*") in find filters.
if [ -z "$commonFilePrefix" ] && [ -n "$file_to_compress" ]; then
    file_to_compress_basename=$(basename -- "$file_to_compress")
    # Trim trailing digits
    commonFilePrefix="${file_to_compress_basename%%+([0-9])}"
fi

compress_exit_code=0

if [[ "${file_to_compress}" ]]; then
    # wait random number of seconds before compressing to avoid to compress log files simultaneously (especially for wiki farms)
    # Use random delay only when env value is a valid positive integer.
    if [[ "${LOG_FILES_COMPRESS_DELAY:-0}" =~ ^[0-9]+$ ]] && [ "${LOG_FILES_COMPRESS_DELAY:-0}" -gt 0 ]; then
        DELAY=$RANDOM
        ((DELAY %= LOG_FILES_COMPRESS_DELAY))
    else
        if [ -n "${LOG_FILES_COMPRESS_DELAY:-}" ] && ! [[ "${LOG_FILES_COMPRESS_DELAY}" =~ ^[0-9]+$ ]]; then
            echo "LOG_FILES_COMPRESS_DELAY is not a non-negative integer (${LOG_FILES_COMPRESS_DELAY:-}), using 0."
        fi
        DELAY=0
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

    LOG_DIRECTORY="$(dirname -- "$file_to_compress")"
    # Keep exactly one trailing slash (needed for symlink directory handling).
    LOG_DIRECTORY="${LOG_DIRECTORY%/}/"

    # Empty prefix would expand to "*" and affect unrelated files.
    if [ -n "$commonFilePrefix" ]; then
        # remove old log files
        if [ -n "${LOG_FILES_REMOVE_OLDER_THAN_DAYS:-}" ] && [ "${LOG_FILES_REMOVE_OLDER_THAN_DAYS}" != false ]; then
            # Validate mtime value before passing it to find.
            if [[ "${LOG_FILES_REMOVE_OLDER_THAN_DAYS}" =~ ^[0-9]+$ ]]; then
                find "$LOG_DIRECTORY" -type f -mtime "+$LOG_FILES_REMOVE_OLDER_THAN_DAYS" -iname "$commonFilePrefix*" ! -iname ".*" ! -iname "*.current" -exec rm -f {} \;
            else
                echo "LOG_FILES_REMOVE_OLDER_THAN_DAYS is not a non-negative integer (${LOG_FILES_REMOVE_OLDER_THAN_DAYS}), skipping old log removal."
            fi
        fi

        # compress uncompressed old log files
        find "$LOG_DIRECTORY" -type f -mtime "+2" -iname "$commonFilePrefix*" ! -iname ".*" ! -iname "*.current" ! -iname "*.gz" ! -iname "*.zip" ! -iname "*.tar" -exec tar --gzip --create --remove-files --absolute-names --transform 's/.*\///g' --file {}.tar.gz {} \;
    else
        echo "commonFilePrefix is empty, skipping cleanup/compression find operations."
    fi
fi

shopt -u extglob
exit ${compress_exit_code}
