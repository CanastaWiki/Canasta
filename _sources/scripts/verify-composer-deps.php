<?php

/**
 * After composer update, verify that every package required by a merged-in
 * extension's composer.json is actually present in vendor/. Catches the class
 * of failure where a bundled extension (Elastica, SemanticMediaWiki, ...) is
 * enabled but its Composer library was never installed, which otherwise
 * surfaces only as a cryptic "Class ... not found" at request time.
 *
 * Usage: php verify-composer-deps.php <MW_HOME>
 *
 * Prints a line per missing package and exits non-zero if any are missing, so
 * it can gate the image build (see extensions-skins.php) and the startup
 * update (see update-composer-deps.sh). Exits 0 when the vendor/ is complete
 * or there is nothing to check.
 */

$mwHome = $argv[1] ?? getenv('MW_HOME');
if (!$mwHome) {
    exit(0);
}

$composerLocal = "$mwHome/composer.local.json";
$installedPath = "$mwHome/vendor/composer/installed.json";
if (!is_file($composerLocal) || !is_file($installedPath)) {
    exit(0);
}

$local = json_decode(file_get_contents($composerLocal), true);
$includes = $local['extra']['merge-plugin']['include'] ?? [];
if (!$includes) {
    exit(0);
}

// Collect the set of satisfiable package names from installed.json: each
// installed package's own name plus anything it provides or replaces (so
// virtual packages don't read as missing).
$installedRaw = json_decode(file_get_contents($installedPath), true);
$packages = $installedRaw['packages'] ?? $installedRaw;
$available = [];
foreach ($packages as $pkg) {
    foreach ([[$pkg['name'] ?? null], array_keys($pkg['provide'] ?? []),
              array_keys($pkg['replace'] ?? [])] as $names) {
        foreach ($names as $name) {
            if ($name !== null) {
                $available[strtolower($name)] = true;
            }
        }
    }
}

$missing = [];
foreach ($includes as $pattern) {
    foreach (glob("$mwHome/$pattern") as $extComposer) {
        $data = json_decode(file_get_contents($extComposer), true);
        if (!is_array($data)) {
            continue;
        }
        $extName = basename(dirname($extComposer));
        foreach (array_keys($data['require'] ?? []) as $package) {
            $name = strtolower($package);
            // Skip platform requirements and virtual meta-packages, which are
            // not installed as entries in vendor/.
            if ($name === 'php' || strpos($name, '/') === false
                || strpos($name, 'ext-') === 0 || strpos($name, 'lib-') === 0) {
                continue;
            }
            if (!isset($available[$name])) {
                $missing[] = "$extName requires $package";
            }
        }
    }
}

if ($missing) {
    fwrite(STDERR, "ERROR: Composer dependencies missing after install — "
        . "composer.local.json or vendor/ is incomplete:\n");
    foreach (array_unique($missing) as $entry) {
        fwrite(STDERR, "  - $entry\n");
    }
    exit(1);
}

exit(0);
