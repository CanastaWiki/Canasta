#!/bin/bash

# Use relative symlinks so they work both inside the container and when
# code is extracted to the host for development/debugging

echo "Symlinking bundled extensions..."
for bundled_extension_path in $(find $MW_HOME/canasta-extensions/ -maxdepth 1 -mindepth 1 -type d)
do
  bundled_extension_id=$(basename $bundled_extension_path)
  target="$MW_HOME/extensions/$bundled_extension_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn ../canasta-extensions/$bundled_extension_id $target
done

echo "Symlinking bundled skins..."
for bundled_skin_path in $(find $MW_HOME/canasta-skins/ -maxdepth 1 -mindepth 1 -type d)
do
  bundled_skin_id=$(basename $bundled_skin_path)
  target="$MW_HOME/skins/$bundled_skin_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn ../canasta-skins/$bundled_skin_id $target
done

echo "Symlinking user extensions and overwriting any redundant bundled extensions..."
for user_extension_path in $(find $MW_HOME/user-extensions/ -maxdepth 1 -mindepth 1 \( -type d -o -type l \))
do
  user_extension_id=$(basename $user_extension_path)
  target="$MW_HOME/extensions/$user_extension_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn ../user-extensions/$user_extension_id $target
done

echo "Symlinking user skins and overwriting any redundant bundled skins..."
for user_skin_path in $(find $MW_HOME/user-skins/ -maxdepth 1 -mindepth 1 \( -type d -o -type l \))
do
  user_skin_id=$(basename $user_skin_path)
  target="$MW_HOME/skins/$user_skin_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn ../user-skins/$user_skin_id $target
done
