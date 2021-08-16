#!/bin/sh
# @author Greg Rundlett <greg@equality-tech.com>
# This script will create backups of all the wiki databases

wikis="de en es fr it ja ko pt ru sv zh"

for wiki in $wikis; do
        echo "working on $wiki...";
        command="/backup_scripts/backup.db.sh wiki_$wiki";
        command="WIKI=$wiki $command";

        echo "using $command";
        $command;
        echo "done with $wiki";
done
