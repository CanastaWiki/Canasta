#!/bin/bash

echo "Symlinking bundled extensions..."
find $MW_HOME/canasta-extensions/ -maxdepth 1 -mindepth 1 -type d -exec sh -c '
    bundled_extension_id=$(basename "$1")
    ln -s "$MW_HOME/canasta-extensions/$bundled_extension_id/" "$MW_HOME/extensions/$bundled_extension_id"
' shell {} \;

echo "Symlinking bundled skins..."
find $MW_HOME/canasta-skins/ -maxdepth 1 -mindepth 1 -type d -exec sh -c '
    bundled_skin_id=$(basename "$1")
    ln -s "$MW_HOME/canasta-skins/$bundled_skin_id/" "$MW_HOME/skins/$bundled_skin_id"
' shell {} \;

echo "Symlinking user extensions and overwriting any redundant bundled extensions..."
find $MW_HOME/user-extensions/ -maxdepth 1 -mindepth 1 -type d -exec sh -c '
    user_extension_id=$(basename "$1")
    ln -sf "$MW_HOME/user-extensions/$user_extension_id/" "$MW_HOME/extensions/$user_extension_id"
' shell {} \;

echo "Symlinking user skins and overwriting any redundant bundled skins..."
find $MW_HOME/user-skins/ -maxdepth 1 -mindepth 1 -type d -exec sh -c '
    user_skin_id=$(basename "$1")
    ln -sf "$MW_HOME/user-skins/$user_skin_id/" "$MW_HOME/skins/$user_skin_id"
' shell {} \;
