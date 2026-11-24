#!/usr/bin/env bash
set -x

. /functions.sh

userexts="$MW_HOME/user-extensions"
extensions="$MW_HOME/extensions"
canexts="$MW_HOME/canasta-extensions"

userskins="$MW_HOME/user-skins"
skins="$MW_HOME/skins"
canskins="$MW_HOME/canasta-skins"

#  - Detects changes inside user-extensions / user-skins and maintains
#    symlinks into extensions / skins (user-extensions -> extensions,
#    user-skins -> skins).
#  - When an entry is removed or moved out, reverts to the bundled copy in
#    canasta-extensions / canasta-skins if present, otherwise removes the link.
#
# Event handling does not trust inotify's ISDIR flag. Docker Desktop on macOS
# propagates host-side bind-mount events without it, so a directory create
# arrives as a bare CREATE. We stat the source path to decide whether to link
# instead of matching on the flag, which keeps live detection working there.

# Reads "event:file" lines (inotifywait --format '%e:%f') from stdin and
# maintains the symlinks for one directory pair.
# Args: <user_dir> <link_dir> <canonical_dir>
handle_dir_events() {
  local user_dir=$1 link_dir=$2 canonical_dir=$3
  local event file
  while IFS=: read -r event file; do
    [ -n "$file" ] || continue
    case $event in
      CREATE*|MOVED_TO*)
        # Only link directories (extensions/skins are dirs); ignore files.
        [ -d "$user_dir/$file" ] && ln -sfn -- "$user_dir/$file" "$link_dir/$file"
        ;;
      DELETE*|MOVED_FROM*)
        # Only touch links we manage; leave unrelated entries alone.
        if [ -L "$link_dir/$file" ] || [ ! -e "$link_dir/$file" ]; then
          if [ -e "$canonical_dir/$file" ]; then
            ln -sfn -- "$canonical_dir/$file" "$link_dir/$file"
          else
            rm -f -- "$link_dir/$file"
          fi
        fi
        ;;
    esac
  done
}

# Watch one directory for changes and feed events to handle_dir_events.
# Args: <user_dir> <link_dir> <canonical_dir>
watch_dir() {
  inotifywait -m -e create,moved_to,delete,moved_from --format '%e:%f' -- "$1" |
    handle_dir_events "$1" "$2" "$3"
}

# When sourced (e.g. by the tests) stop here so the watchers do not run.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
  return 0
fi

# Disable directory monitoring
if isTrue "$DISABLE_DIRECTORY_MONITOR"; then
  echo "Directory monitoring is disabled via DISABLE_DIRECTORY_MONITOR"
  exit 0
fi

# Watch both directories concurrently. The previous sequential form left the
# skins watcher unreachable because `inotifywait -m` never returns.
watch_dir "$userexts" "$extensions" "$canexts" &
watch_dir "$userskins" "$skins" "$canskins" &
wait
