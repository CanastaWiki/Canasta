#!/usr/bin/env bash

# Check if BOOTSTRAP_LOGFILE is defined and not empty
if [ -n "$BOOTSTRAP_LOGFILE" ]; then
    # If BOOTSTRAP_LOGFILE is defined, set up logging
    # Open file descriptor 3 for logging xtrace output
    exec 3>>"$BOOTSTRAP_LOGFILE"
    BASH_XTRACEFD=3
fi
set -x

userexts="$MW_HOME/user-extensions"
extensions="$MW_HOME/extensions"
canexts="$MW_HOME/canasta-extensions"

userskins="$MW_HOME/user-skins"
skins="$MW_HOME/skins"
canskins="$MW_HOME/canasta-skins"

#  - Detects activity changes inside user-extensions and user-skins.
#  - Adds symlinks from the those folders to the appropriate correspondent folders, user-extensions to extensions and user-skins to skins.
#  - As a fallback, the moment the extension is removed or moved from user-extensions it will revert back by adding a symlink to the extension
#    located in canasta-extensions.

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f' -- "$userexts" |
	while IFS=: read -r event file; do
		case $event in
			CREATE,ISDIR|MOVED_TO,ISDIR)
				ln -rsft "$extensions" -- "$userexts"/"$file" ;;
			DELETE,ISDIR|MOVED_FROM,ISDIR)
				echo "event: ${event} file: ${file}";
				ln -rsft "$extensions" -- "$canexts"/"$file" || rm -- "$file";
		esac
	done

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f' -- "$userskins" |
	while IFS=: read -r event file; do
		case $event in
			CREATE,ISDIR|MOVED_TO,ISDIR)
				ln -rsft "$skins" -- "$userskins"/"$file" ;;
			DELETE,ISDIR|MOVED_FROM,ISDIR)
				echo "event: ${event} file: ${file}";
				ln -rsft "$skins" -- "$canskins"/"$file" || rm -- "$file";
		esac
	done
