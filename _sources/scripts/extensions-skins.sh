#!/bin/bash

MW_HOME="$MW_HOME"
MW_VERSION="$MW_VERSION"
type=$1
path=$2
# Since yq cannot process data from variables, a conversion is made to JSON format to utilise jq.
commands=$(yq eval '. | to_json' $path)
echo "$commands" | jq -r ".$type" | jq -c '.[]' | while read -r obj; do
    data=$(echo "$obj" | jq -r 'keys_unsorted[] as $key | select(has($key)) | "\($key) \(.[$key].repository) \(.[$key].commit) \(.[$key].branch)"')
    read -r name repository commit branch <<< "$data"
    
    git_clone_cmd="git clone "
    if [ "$repository" == "null" ]; then
        repository="https://github.com/wikimedia/mediawiki-$type-$name" 
        if [ "$branch" == "null" ]; then
            branch=$MW_VERSION
            git_clone_cmd="$git_clone_cmd --single-branch -b $branch"    
        fi
    fi
    git_clone_cmd="$git_clone_cmd $repository $MW_HOME/$type/$name"
    git_checkout_cmd="cd $MW_HOME/$type/$name && git checkout -q $commit"

    eval "$git_clone_cmd && $git_checkout_cmd"
    patches=$(echo "$obj" | jq -r ".$name.patches")
    if [ "$patches" != "null" ]; then
        echo "$patches" | jq -c '.[]' | while read -r patch; do
            git_apply_cmd="cd $MW_HOME/$type/$name && git apply /tmp/$patch"
            eval "$git_apply_cmd"
        done
    fi
done
