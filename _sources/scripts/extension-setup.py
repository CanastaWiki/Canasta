#!/bin/python3

import os
import yaml
# Define MW_HOME directory
MW_HOME = os.environ["MW_HOME"]
MW_VERSION = os.environ["MW_VERSION"]

# Read commands from YAML file
with open('/tmp/extensions.yaml', 'r') as file:
    commands = yaml.safe_load(file)

# Iterate over commands
for command in commands['commands']:
    for extension, info in command.items():
        repository = info['repository']
        commit = info['commit']

        git_clone_cmd = "git clone "
        
        if "branch" in info.keys():
            branch = info['branch']

            if branch == "MW_VERSION":
                branch = MW_VERSION

            git_clone_cmd += f"--single-branch -b {branch} "
            
        git_clone_cmd += f"{repository} {MW_HOME}/extensions/{extension}"
        # Construct git checkout command
        git_checkout_cmd = f"cd {MW_HOME}/extensions/{extension} && git checkout -q {commit}"
        
        # Execute commands
        os.system(git_clone_cmd)
        os.system(git_checkout_cmd)
