#!/bin/bash

# Use relative symlinks so they work both inside the container and when
# code is extracted to the host for development/debugging

echo "Symlinking bundled extensions..."
while IFS= read -r -d '' bundled_extension_path
do
  bundled_extension_id=$(basename "$bundled_extension_path")
  target="$MW_HOME/extensions/$bundled_extension_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn "../canasta-extensions/$bundled_extension_id" "$target"
done < <(find "$MW_HOME/canasta-extensions/" -maxdepth 1 -mindepth 1 -type d -print0)

echo "Symlinking bundled skins..."
while IFS= read -r -d '' bundled_skin_path
do
  bundled_skin_id=$(basename "$bundled_skin_path")
  target="$MW_HOME/skins/$bundled_skin_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn "../canasta-skins/$bundled_skin_id" "$target"
done < <(find "$MW_HOME/canasta-skins/" -maxdepth 1 -mindepth 1 -type d -print0)

echo "Symlinking user extensions and overwriting any redundant bundled extensions..."
while IFS= read -r -d '' user_extension_path
do
  user_extension_id=$(basename "$user_extension_path")
  target="$MW_HOME/extensions/$user_extension_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn "../user-extensions/$user_extension_id" "$target"
done < <(find "$MW_HOME/user-extensions/" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -print0)

echo "Symlinking user skins and overwriting any redundant bundled skins..."
while IFS= read -r -d '' user_skin_path
do
  user_skin_id=$(basename "$user_skin_path")
  target="$MW_HOME/skins/$user_skin_id"
  # Remove existing directory (not symlink) before creating symlink
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi
  ln -sfn "../user-skins/$user_skin_id" "$target"
done < <(find "$MW_HOME/user-skins/" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -print0)
