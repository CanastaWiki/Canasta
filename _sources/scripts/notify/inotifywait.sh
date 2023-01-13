#!/usr/bin/env bash
set -x

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f%0' user-extensions | while IFS=: read -r event file; do case $event in CREATE,ISDIR|MOVED_TO,ISDIR) ln -rsft extensions -- user-extensions/"$file" ;; DELETE,ISDIR|MOVED_FROM,ISDIR) echo "event: ${event}   file: ${file}"; ln -rsft extensions -- canasta-extensions/"$file" || rm -- "$file"; esac done

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f%0' user-skins | while IFS=: read -r event file; do case $event in CREATE,ISDIR|MOVED_TO,ISDIR) ln -rsft skins -- user-skins/"$file" ;; DELETE,ISDIR|MOVED_FROM,ISDIR) echo "event: ${event}   file: ${file}"; ln -rsft skins -- canasta-skins/"$file" || rm -- "$file"; esac done
