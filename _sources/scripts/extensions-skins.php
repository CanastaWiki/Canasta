<!-- It is much easier to do parsing of YAML in PHP than in .sh; the standard way to do YAML parsing
in a shell script is to call yq, but yq requires different executables for different architectures. 
Given that the YAML parsing is already in PHP, it seemed easier to do the whole thing in PHP rather 
than split the work between two scripts -->
<?php

$MW_HOME = getenv("MW_HOME");
$MW_VERSION = getenv("MW_VERSION");
$MW_VOLUME = getenv("MW_VOLUME");
$MW_ORIGIN_FILES = getenv("MW_ORIGIN_FILES");
$type = $argv[1];
$path = $argv[2];

$yamlData = yaml_parse_file($path);

foreach ($yamlData[$type] as $obj) {
    $name = key($obj);
    $data = $obj[$name];
    
    $repository = $data['repository'] ?? null;
    $commit = $data['commit'] ?? null;
    $branch = $data['branch'] ?? null;
    $patches = $data['patches'] ?? null;
    $persistentDirectories = $data['persistent-directories'] ?? null;
    $additionalSteps = $data['additional steps'] ?? null;
    $bundled = $data['bundled'] ?? false;

    // Installation of extensions using their Composer package -
    // this is not currently used, but it may in the future.
    if ($data['composer-name']) {
        $packageName = $data['composer-name'];
        $packageVersion = $data['composer-version'] ?? null;
        $packageString = $packageVersion ? "$packageName:$packageVersion" : $packageName;
        exec("composer require $packageString --working-dir=$MW_HOME --no-interaction");
        continue;
    }

    if ($persistentDirectories !== null) {
        exec("mkdir -p $MW_ORIGIN_FILES/canasta-$type/$name");
        foreach ($directory as $persistentDirectories) {
            exec("mv $MW_HOME/canasta-$type/$name/$directory $MW_ORIGIN_FILES/canasta-$type/$name/");
            exec("ln -s $MW_VOLUME/canasta-$type/$name/$directory $MW_HOME/canasta-$type/$name/$directory");
        }
    }
    
    if (!$bundled) {
        $gitCloneCmd = "git clone ";
        
        if ($repository === null) {
            $repository = "https://github.com/wikimedia/mediawiki-$type-$name";
            if ($branch === null) {
                $branch = $MW_VERSION;
                $gitCloneCmd .= "--single-branch -b $branch ";
            }
        }
        
        $gitCloneCmd .= "$repository $MW_HOME/$type/$name";
        $gitCheckoutCmd = "cd $MW_HOME/$type/$name && git checkout -q $commit";

        exec($gitCloneCmd);
        exec($gitCheckoutCmd);

        if ($patches !== null) {
            foreach ($patches as $patch) {
                $gitApplyCmd = "cd $MW_HOME/$type/$name && git apply /tmp/$patch";
                exec($gitApplyCmd);
            }
        }
    }

    if ($additionalSteps !== null) {
        foreach ($additionalSteps as $step) {
            if ($step === "composer update") {
                $composerInstallCmd = "composer install --working-dir=$MW_HOME/$type/$name --no-interaction --no-dev";
                shell_exec("$composerInstallCmd");
            } elseif ($step === "git submodule update") {
                $submoduleUpdateCmd = "cd $MW_HOME/$type/$name && git submodule update --init";
                exec($submoduleUpdateCmd);
            }
        }
    }
}

?>
