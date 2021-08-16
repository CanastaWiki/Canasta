#!/bin/sh
# @author Greg Rundlett <info@eQuality-Tech.com>
# This is a quick shell script to create a sql dump of your database.
# You may need to adjust the path of mysqldump, 
# or sudo apt-get install mysqldump  if it doesn't exist

# We'll make it so you can pass the database name as the first parameter 
# to the script for playbook / cron / non-interactive use
# If no parameter is passed, we'll prompt you for the name
DB=$1
if [ $# -ne 1 ]; then 
  echo "Here are the current databases on the server"
  mysql -u root -h db -pmediawiki --batch --skip-column-names -e 'show databases;'
  echo "Enter the name of the database you want to backup"
  read DB
fi
# If on a Virtual Machine, use a location that is exported to the host, 
# so that our backups are accessible even if the virtual machine is no longer accessible.
# backupdir="/vagrant/mediawiki/backups";
backupdir="/backups";



if [ ! -d "$backupdir" ]; then
  mkdir -p "$backupdir";
fi

# shell parameter expansion 
# see http://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
# we'll start with a default backup file named '01' in the sequence
backup="${backupdir}/dump-$(date +%F).$(hostname)-${DB}.01.sql";
# and we'll increment the counter in the filename if it already exists
i=1
filename=$(basename "$backup") # foo.txt (basename is everything after the last slash)
extension=${filename##*.}             # .txt (filename with the longest matching pattern of *. being deleted)
file=${filename%.*}                         # foo (filename with the shortest matching pattern of .* deleted)
file=${file%.*}                                  # repeat the strip to get rid of the counter
# file=${filename%.{00..99}.$extension} # foo (filename with the shortest matching pattern of .[01-99].* deleted)
while [ -f $backup ]; do
  backup="$backupdir/${file}.$(printf '%.2d' $(( i+1 ))).${extension}"
  i=$(( i+1 ))  # increments $i 
  # note that i is naked because $(( expression )) is arithmetic expansion in bash
done
if /usr/bin/mysqldump -u root -h db -pmediawiki --single-transaction "$DB" > "$backup"; then
  echo "Backup created successfully"
  echo " compressing..."
  gzip $backup
  ls -al "${backup}.gz";
  echo "A command such as"
  echo "mysql -u root $DB <<( zcat ${backup}.gz)" 
  echo "will restore the database from the chosen sql dump file"
else
  echo "ERROR: Something went wrong with the backup"
  exit 1
fi 
