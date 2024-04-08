#!/bin/sh

MW_HOME="$MW_HOME"
MW_VERSION="$MW_VERSION"
# Since yq cannot process data from variables, a conversion is made to JSON format to utilise jq.
commands=$(yq eval '. | to_json' extensions.yaml)
echo "$commands" | jq -r '.extensions' | jq -c '.[]' | while read -r obj; do
    extension_data=$(echo "$obj" | jq -r 'keys_unsorted[] as $key | select(has($key)) | "\($key) \(.[$key].repository) \(.[$key].commit) \(.[$key].branch)"')
    read -r extension_name repository commit branch <<< "$extension_data"
    
    git_clone_cmd="git clone "
    if [ "$repository" == "null" ]; then
        repository="https://github.com/wikimedia/mediawiki-extensions-$extension_name" 
        if [ "$branch" == "null" ]; then
            branch=$MW_VERSION
            git_clone_cmd="$git_clone_cmd --single-branch -b $branch"    
        fi
    fi
    git_clone_cmd="$git_clone_cmd $repository $MW_HOME/extensions/$extension_name"
    git_checkout_cmd="cd $MW_HOME/extensions/$extension_name && git checkout -q $commit"

    eval "$git_clone_cmd && $git_checkout_cmd"
    patches=$(echo "$obj" | jq -r ".$extension_name.patches")
    if [ "$patches" != "null" ]; then
        echo "$patches" | jq -c '.[]' | while read -r patch; do
            git_apply_cmd="cd $MW_HOME/extensions/$extension_name && git apply /tmp/$patch"
            eval "$git_apply_cmd"
        done
    fi
done
