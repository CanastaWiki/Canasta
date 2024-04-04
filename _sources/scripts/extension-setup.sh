#!/bin/sh

MW_HOME="$MW_HOME"
MW_VERSION="$MW_VERSION"
# Since yq cannot process data from variables, a conversion is made to JSON format to utilise jq.
commands=$(yq eval '. | to_json' extensions.yaml)
echo "$commands" | jq -r '.extensions' | jq -c '.[]' | while read -r obj; do
    extension_name=$(echo "$obj" | jq -r 'keys_unsorted[]')
    repository=$(echo "$obj" | jq -r ".$extension_name.repository")
    commit=$(echo "$obj" | jq -r ".$extension_name.commit")
    branch=$(echo "$obj" | jq -r ".$extension_name.branch")

    git_clone_cmd="git clone "
    if [ "$branch" != "null" ]; then
        if [ "$branch" = "MW_VERSION" ]; then
            branch=$MW_VERSION
        fi
        git_clone_cmd="$git_clone_cmd --single-branch -b $branch "
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
