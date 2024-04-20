#!/bin/bash

MW_HOME="$MW_HOME"
MW_VERSION="$MW_VERSION"
# Since yq cannot process data from variables, a conversion is made to JSON format to utilise jq.
commands=$(yq eval '. | to_json' /tmp/skins.yaml)
echo "$commands" | jq -r '.skins' | jq -c '.[]' | while read -r obj; do
    skin_data=$(echo "$obj" | jq -r 'keys_unsorted[] as $key | select(has($key)) | "\($key) \(.[$key].repository) \(.[$key].commit) \(.[$key].branch)"')
    read -r skin_name repository commit branch <<< "$skin_data"
    
    git_clone_cmd="git clone "
    if [ "$repository" == "null" ]; then
        repository="https://github.com/wikimedia/mediawiki-skins-$skin_name" 
        if [ "$branch" == "null" ]; then
            branch=$MW_VERSION
            git_clone_cmd="$git_clone_cmd --single-branch -b $branch"    
        fi
    fi
    git_clone_cmd="$git_clone_cmd $repository $MW_HOME/skins/$skin_name"
    git_checkout_cmd="cd $MW_HOME/skins/$skin_name && git checkout -q $commit"

    eval "$git_clone_cmd && $git_checkout_cmd"
    patches=$(echo "$obj" | jq -r ".$skin_name.patches")
    if [ "$patches" != "null" ]; then
        echo "$patches" | jq -c '.[]' | while read -r patch; do
            git_apply_cmd="cd $MW_HOME/skins/$skin_name && git apply /tmp/$patch"
            eval "$git_apply_cmd"
        done
    fi
done
