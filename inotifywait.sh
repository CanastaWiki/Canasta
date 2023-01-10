#!/usr/bin/env bash

recursive="--recursive"
exclude=""

sym_create() {
ln -s "${1}" "${2}" 
 return
}
sym_remove() {
unlink "${1}"
return
}
declare -A array=( ["/root/Cani/"]="/root/Cani2/" ["/root/somewhere1/"]="/root/somewhere2/" )
inotifywait --exclude "${exclude:-\$^}" "${recursive}" --monitor "${!array[@]}" |
    while read -r directory event file; do
        case "${event}" in
	 CREATE*|MOVED_TO*)
		if [[ $? -eq 0 ]]; then
		    sym_create "${directory}${file}" "${array["${directory}"]}${file}"
		fi
	    ;;
	
	MOVED_FROM*|DELETE*)
		if [[ $? -eq 0 ]]; then
	            if [[ -n ${file} ]]; then
			sym_remove "${array["${directory}"]}${file}"
              		rm -rf "${array["${directory}"]}${file}"
	            else
			 sym_remove "${array["${directory}"]}"
        	         rm -rf  "${array["${directory}"]}"
	            fi
                fi
            ;;

        esac
    done
