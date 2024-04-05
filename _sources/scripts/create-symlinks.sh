#!/bin/bash

echo "Symlinking bundled extensions..."
for bundled_extension_path in $(find $MW_HOME/canasta-extensions/ -maxdepth 1 -mindepth 1 -type d)
do
  bundled_extension_id=$(basename $bundled_extension_path)
  ln -s $MW_HOME/canasta-extensions/$bundled_extension_id/ $MW_HOME/extensions/$bundled_extension_id
done

echo "Symlinking bundled skins..."
for bundled_skin_path in $(find $MW_HOME/canasta-skins/ -maxdepth 1 -mindepth 1 -type d)
do
  bundled_skin_id=$(basename $bundled_skin_path)
  ln -s $MW_HOME/canasta-skins/$bundled_skin_id/ $MW_HOME/skins/$bundled_skin_id
done

echo "Symlinking user extensions and overwriting any redundant bundled extensions..."
for user_extension_path in $(find $MW_HOME/user-extensions/ -maxdepth 1 -mindepth 1 -type d)
do
  user_extension_id=$(basename $user_extension_path)
  ln -sf $MW_HOME/user-extensions/$user_extension_id/ $MW_HOME/extensions/$user_extension_id
done

echo "Symlinking user skins and overwriting any redundant bundled skins..."
for user_skin_path in $(find $MW_HOME/user-skins/ -maxdepth 1 -mindepth 1 -type d)
do
  user_skin_id=$(basename $user_skin_path)
  ln -sf $MW_HOME/user-skins/$user_skin_id/ $MW_HOME/skins/$user_skin_id
done
