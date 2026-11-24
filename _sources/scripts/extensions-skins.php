<?php

/**
 * It is much easier to do parsing of YAML in PHP than in .sh; the standard way
 * to do YAML parsing in a shell script is to call yq, but yq requires
 * different executables for different architectures.
 *
 * Given that the YAML parsing is already in PHP, we do all the rest of the
 * installation in PHP too: Git download, Composer updates, applying patches,
 * etc. - it seems easier to do everything in one spot.
 */

$MW_HOME = getenv("MW_HOME");
$MW_VERSION = getenv("MW_VERSION");
$MW_VOLUME = getenv("MW_VOLUME");
$MW_ORIGIN_FILES = getenv("MW_ORIGIN_FILES");
$path = $argv[1];

$contentsData = [
    'extensions' => [],
    'skins' => []
];

// Track extensions/skins that need composer dependencies merged
$composerIncludes = [];

populateContentsData($path, $contentsData);

foreach (['extensions', 'skins'] as $type) {
    foreach ($contentsData[$type] as $name => $data) {
        // 'remove: true' allows for child files to remove an extension or
        // skin specified by any of their parent files.
        $remove = $data['remove'] ?? false;
        if ($remove) {
            continue;
        }

        $repository = $data['repository'] ?? null;
        $commit = $data['commit'] ?? null;
        $branch = $data['branch'] ?? null;
        $patches = $data['patches'] ?? null;
        $persistentDirectories = $data['persistent directories'] ?? null;
        $additionalSteps = $data['additional steps'] ?? null;
        $bundled = $data['bundled'] ?? false;
        $requiredExtensions = $data['required extensions'] ?? null;

        // Installation of extensions using their composer package (for SMW, etc.,)
        if ($data['composer-name'] ?? null) {
            $packageName = $data['composer-name'];
            $packageVersion = $data['composer-version'] ?? null;
            $packageString = $packageVersion ? "$packageName:$packageVersion" : $packageName;
            exec("composer require $packageString --working-dir=$MW_HOME --no-interaction", $requireOutput, $requireReturnCode);
            if ($requireReturnCode !== 0) {
                fwrite(STDERR, "ERROR: composer require $packageString failed for $type/$name (exit $requireReturnCode). Aborting the build.\n");
                exit($requireReturnCode);
            }
        }

        if (!$bundled && !($data['composer-name'] ?? null)) {
            $gitCloneCmd = "git clone ";

            if ($repository === null) {
                $repository = "https://github.com/wikimedia/mediawiki-$type-$name";
                if ($branch === null) {
                    $branch = $MW_VERSION;
                    $gitCloneCmd .= "--single-branch -b $branch ";
                }
            }

            $gitCloneCmd .= "$repository $MW_HOME/canasta-$type/$name";
            $gitCheckoutCmd = "cd $MW_HOME/canasta-$type/$name && git checkout -q $commit";

            // Fail the build on a git failure instead of shipping the
            // extension at the wrong revision. A clone failure leaves nothing;
            // a failed checkout (e.g. an unreachable pinned commit) silently
            // leaves the extension on the clone's default branch or branch
            // HEAD, which ships code that was never intended.
            exec($gitCloneCmd, $cloneOutput, $cloneReturnCode);
            if ($cloneReturnCode !== 0) {
                fwrite(STDERR, "ERROR: git clone failed for $type/$name (exit $cloneReturnCode). Aborting the build.\n");
                exit($cloneReturnCode);
            }
            exec($gitCheckoutCmd, $checkoutOutput, $checkoutReturnCode);
            if ($checkoutReturnCode !== 0) {
                fwrite(STDERR, "ERROR: git checkout $commit failed for $type/$name (exit $checkoutReturnCode); the pinned commit may be unreachable. Aborting the build.\n");
                exit($checkoutReturnCode);
            }
        }

        if ($patches !== null) {
            foreach ($patches as $patch) {
                $gitApplyCmd = "cd $MW_HOME/canasta-$type/$name && git apply /tmp/$patch";
                exec($gitApplyCmd, $applyOutput, $applyReturnCode);
                if ($applyReturnCode !== 0) {
                    fwrite(STDERR, "ERROR: git apply /tmp/$patch failed for $type/$name (exit $applyReturnCode); the extension would ship unpatched. Aborting the build.\n");
                    exit($applyReturnCode);
                }
            }
        }

        if ($additionalSteps !== null) {
            foreach ($additionalSteps as $step) {
                if ($step === "composer update") {
                    // Dependencies will be resolved by the unified root-level composer update below.
                    $composerIncludes[] = "$type/$name/composer.json";
                } elseif ($step === "git submodule update") {
                    $submoduleUpdateCmd = "cd $MW_HOME/canasta-$type/$name && git submodule update --init";
                    exec($submoduleUpdateCmd, $submoduleOutput, $submoduleReturnCode);
                    if ($submoduleReturnCode !== 0) {
                        fwrite(STDERR, "ERROR: git submodule update failed for $type/$name (exit $submoduleReturnCode). Aborting the build.\n");
                        exit($submoduleReturnCode);
                    }
                }
            }
        }

        // Generate gitinfo.json before removing .git, so Special:Version can show commit info
        $extPath = "$MW_HOME/canasta-$type/$name";
        $hash = trim(shell_exec("cd $extPath && git rev-parse HEAD 2>/dev/null") ?? '');
        if ($hash) {
            $date = trim(shell_exec("cd $extPath && git log -1 --format=%ct HEAD 2>/dev/null") ?? '');
            $branch = trim(shell_exec("cd $extPath && git rev-parse --abbrev-ref HEAD 2>/dev/null") ?? '');
            $remote = trim(shell_exec("cd $extPath && git config --get remote.origin.url 2>/dev/null") ?? '');
            $gitinfo = [
                'head' => $hash,
                'headSHA1' => $hash,
                'headCommitDate' => $date,
                'branch' => $branch,
                'remoteURL' => $remote
            ];
            file_put_contents("$extPath/gitinfo.json", json_encode($gitinfo));
        }

        // Remove .git directory after all git operations are complete, to reduce the size of the Docker image
        exec("rm -rf $MW_HOME/canasta-$type/$name/.git");

        if ($persistentDirectories !== null) {
            exec("mkdir -p $MW_ORIGIN_FILES/$type/$name");
            foreach ($persistentDirectories as $directory) {
                exec("mv $MW_HOME/canasta-$type/$name/$directory $MW_ORIGIN_FILES/$type/$name/");
                exec("ln -s $MW_VOLUME/$type/$name/$directory $MW_HOME/canasta-$type/$name/$directory");
            }
        }
    }
}

// Create build-time symlinks in extensions/ and skins/ pointing to
// canasta-extensions/ and canasta-skins/. This mirrors what create-symlinks.sh
// does at runtime, but without user-extensions/user-skins (which don't exist
// at build time). The symlinks let composer.local.json reference extensions by
// their canonical extensions/Name/ path at both build time and runtime.
echo "Creating build-time symlinks for canasta extensions and skins...\n";
foreach (['extensions' => 'canasta-extensions', 'skins' => 'canasta-skins'] as $target => $source) {
    foreach (glob("$MW_HOME/$source/*", GLOB_ONLYDIR) as $dir) {
        $name = basename($dir);
        $link = "$MW_HOME/$target/$name";
        if (!file_exists($link)) {
            symlink("../$source/$name", $link);
        }
    }
}

// Save the bundled extensions/skins that have composer dependencies as the
// image's include list. We use specific entries rather than wildcards to
// avoid broken composer.json files in extensions that don't need composer.
// The instance's config/composer.local.json holds only the operator's
// additions; composer-local.php merges them over this list into
// composer.local.json, here and at startup.
$composerBundled = [
    'extra' => [
        'merge-plugin' => [
            'include' => $composerIncludes
        ]
    ]
];
file_put_contents("$MW_HOME/composer.canasta.json",
    json_encode($composerBundled, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
$composerLocalCmd = "php " . escapeshellarg("$MW_HOME/maintenance/composer-local.php")
    . " " . escapeshellarg($MW_HOME)
    . " " . escapeshellarg("$MW_HOME/composer.canasta.json")
    . " /nonexistent"
    . " " . escapeshellarg("$MW_HOME/composer.local.json");
exec($composerLocalCmd, $composerLocalOutput, $composerLocalReturnCode);
if ($composerLocalReturnCode !== 0) {
    fwrite(STDERR, "ERROR: composer-local.php failed (exit $composerLocalReturnCode). Aborting the build.\n");
    exit($composerLocalReturnCode);
}
$composerDepsHash = trim($composerLocalOutput[0] ?? '');

// Run unified composer update at the MediaWiki root.
// Fail the build on a non-zero exit instead of shipping an image whose
// vendor/ is missing the bundled extensions' Composer dependencies. A
// version conflict between MediaWiki core and a bundled extension (e.g. an
// incompatible wikimedia/css-sanitizer pin) makes resolution fail and
// install nothing, which previously surfaced only as a runtime
// "Class ... not found" fatal in the shipped image.
echo "Running unified composer update...\n";
$composerUpdateCmd = "composer update --working-dir=$MW_HOME --no-dev --no-interaction";
passthru($composerUpdateCmd, $composerReturnCode);
if ($composerReturnCode !== 0) {
    fwrite(STDERR, "ERROR: composer update exited with code $composerReturnCode; "
        . "bundled extension dependencies were not installed. Aborting the build.\n");
    exit($composerReturnCode);
}

// Belt-and-suspenders: composer can exit 0 while the merge plugin silently
// skips an include, so verify every merged-in extension's required packages
// actually landed in vendor/. A miss means a broken image — fail the build.
$verifyScript = "$MW_HOME/maintenance/verify-composer-deps.php";
if (is_file($verifyScript)) {
    passthru("php " . escapeshellarg($verifyScript) . " " . escapeshellarg($MW_HOME), $verifyReturnCode);
    if ($verifyReturnCode !== 0) {
        fwrite(STDERR, "ERROR: composer dependency self-test failed. Aborting the build.\n");
        exit($verifyReturnCode);
    }
}

// Record the operator-content hash vendor/ was built for, so the startup
// update runs composer only for the operator's additions.
// The hash file lives at $MW_HOME/.composer-deps-hash, INSIDE the
// container (not on the bind-mounted $MW_VOLUME). vendor/ is also
// intra-container, so the hash and the deps it describes share the
// same lifetime: when the container is recreated, both go away
// together and update-composer-deps.sh correctly re-runs composer. See #141.
file_put_contents("$MW_HOME/.composer-deps-hash", $composerDepsHash . "\n");

/**
 * Recursive function to allow for loading a whole chain of YAML files (if
 * necessary), with each one defining its parent file via the "inherits"
 * field.
 *
 * This function populates the array $contentsData, with child YAML files
 * given the opportunity to overwrite what their parent file(s) specified
 * for any given extension or skin.
 */
function populateContentsData($pathOrURL, &$contentsData) {
    $yamlText = file_get_contents($pathOrURL);
    // If it's stored in, or came from, a MediaWiki wiki (such as
    // mediawiki.org), it may have a <syntaxhighlight> tag around it.
    if ( preg_match( '/<syntaxhighlight\s+lang=["\']yaml["\']>(.*?)<\/syntaxhighlight>/si', $yamlText, $matches ) ) {
        $yamlText = $matches[1];
    }
    $dataFromFile = yaml_parse($yamlText);

    if (array_key_exists('inherits', $dataFromFile)) {
        populateContentsData($dataFromFile['inherits'], $contentsData);
    }

    if (array_key_exists('extensions', $dataFromFile)) {
        foreach ($dataFromFile['extensions'] as $obj) {
            $extensionName = key($obj);
            $extensionData = $obj[$extensionName];
            $contentsData['extensions'][$extensionName] = $extensionData;
        }
    }

    if (array_key_exists('skins', $dataFromFile)) {
        foreach ($dataFromFile['skins'] as $obj) {
            $skinName = key($obj);
            $skinData = $obj[$skinName];
            $contentsData['skins'][$skinName] = $skinData;
        }
    }
}

?>
