#!/usr/bin/env bash
set -x

userexts="$MW_HOME/user-extensions"
extensions="$MW_HOME/extensions"
canexts="$MW_HOME/canasta-extensions"

userskins="$MW_HOME/user-skins"
skins="$MW_HOME/skins"
canskins="$MW_HOME/canasta-skins"

#Detects changes on the user-extensions and user-skins directories and symlinks to each directory skins and extensions else if removed it defaults back to
#canasta-extensions or canasta-skins

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f%0' -- "$userexts" | 
	while IFS=: read -r event file; do 
		case $event in 
			CREATE,ISDIR|MOVED_TO,ISDIR) 
				ln -rsft "$extensions" -- "$userexts"/"$file" ;; 
			DELETE,ISDIR|MOVED_FROM,ISDIR) 
				echo "event: ${event} file: ${file}"; 
				ln -rsft "$extensions" -- "$canexts"/"$file" || rm -- "$file";
		esac 
	done

inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f%0' -- "$userskins" | 
	while IFS=: read -r event file; do 
		case $event in 
			CREATE,ISDIR|MOVED_TO,ISDIR) 
				ln -rsft skins -- "$userskins"/"$file" ;; 
			DELETE,ISDIR|MOVED_FROM,ISDIR) 
				echo "event: ${event} file: ${file}"; 
				ln -rsft skins -- "$canskins"/"$file" || rm -- "$file"; 
		esac 
	done
