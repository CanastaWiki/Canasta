<?php

/**
 * Write MediaWiki's root composer.local.json for this container and print a
 * hash of the operator's Composer content.
 *
 * Usage: php composer-local.php <MW_HOME> <canasta.json> <operator.json> <output.json>
 *
 * <canasta.json> is the image's list, generated at build time from the bundled
 * extensions and skins that need Composer. <operator.json> is the instance's
 * config/composer.local.json; it may be missing. The output starts from the
 * bundled file, minus extra.canasta.exclude-bundled. The operator's require
 * and repositories are added to the bundled ones, and its includes are
 * appended to the bundled list. Every other operator key is carried over,
 * merging objects key by key with the operator's value winning, except
 * extra.canasta, which is read here and not passed to composer.
 *
 * An include counts as the operator's only when its composer.json resolves
 * into user-extensions/ or user-skins/, or outside MW_HOME. Includes that
 * resolve to code shipped in the image are dropped, since only the bundled
 * list decides those, and so are includes that match nothing. A bundled
 * include whose extension or skin is overridden by a user one counts as the
 * operator's too.
 *
 * The hash covers only the operator content, so it is the same with no
 * operator content as at build time, and composer runs only when the
 * operator's additions change.
 */

if ($argc !== 5) {
    fwrite(STDERR, "Usage: php composer-local.php <MW_HOME> <canasta.json> <operator.json> <output.json>\n");
    exit(2);
}
[, $mwHome, $bundledPath, $operatorPath, $outputPath] = $argv;
$mwHome = rtrim($mwHome, '/');

$bundled = readJson($bundledPath) ?? [];
$operator = readJson($operatorPath, 3) ?? [];

$bundledIncludes = stringList($bundled['extra']['merge-plugin']['include'] ?? []);
$operatorIncludes = stringList($operator['extra']['merge-plugin']['include'] ?? []);
$excluded = array_values(array_intersect(
    stringList($operator['extra']['canasta']['exclude-bundled'] ?? []),
    $bundledIncludes
));
sort($excluded);
$require = is_array($operator['require'] ?? null) ? $operator['require'] : [];
$repositories = is_array($operator['repositories'] ?? null) ? $operator['repositories'] : [];

$carried = $operator;
unset($carried['require'], $carried['repositories'], $carried['extra']['canasta'],
    $carried['extra']['merge-plugin']['include']);
$carried = pruneEmpty($carried);

$includes = [];
$operatorFiles = [];
foreach ($bundledIncludes as $pattern) {
    if (in_array($pattern, $excluded, true)) {
        continue;
    }
    $includes[] = $pattern;
    foreach (matchInclude($mwHome, $pattern) as $rel => $file) {
        if (isOperatorFile($mwHome, $file)) {
            $operatorFiles[$rel] = md5_file($file);
        }
    }
}
foreach ($operatorIncludes as $pattern) {
    foreach (matchInclude($mwHome, $pattern) as $rel => $file) {
        if (!isOperatorFile($mwHome, $file)) {
            continue;
        }
        $operatorFiles[$rel] = md5_file($file);
        if (!in_array($rel, $includes, true)) {
            $includes[] = $rel;
        }
    }
}
ksort($operatorFiles);

$effective = deepMerge($bundled, $carried);
$effective['extra']['merge-plugin']['include'] = $includes;
if ($require) {
    $effective['require'] = array_merge($bundled['require'] ?? [], $require);
}
if ($repositories) {
    $effective['repositories'] = array_merge($bundled['repositories'] ?? [], $repositories);
}
$json = json_encode($effective, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
if (file_put_contents($outputPath, $json) === false) {
    fwrite(STDERR, "ERROR: cannot write $outputPath\n");
    exit(1);
}

echo md5(json_encode([
    'require' => $require,
    'repositories' => $repositories,
    'includes' => $operatorFiles,
    'exclude-bundled' => $excluded,
    'other' => canonical($carried),
], JSON_UNESCAPED_SLASHES)) . "\n";

function isObject($value): bool {
    return is_array($value) && $value && !array_is_list($value);
}

function deepMerge(array $base, array $over): array {
    foreach ($over as $key => $value) {
        $base[$key] = isObject($value) && isObject($base[$key] ?? null)
            ? deepMerge($base[$key], $value)
            : $value;
    }
    return $base;
}

/**
 * Drop empty arrays, which json_decode makes of both {} and [], so an
 * emptied object neither reaches composer as [] nor counts as content.
 */
function pruneEmpty(array $data): array {
    $isList = array_is_list($data);
    foreach ($data as $key => $value) {
        if (is_array($value)) {
            $value = pruneEmpty($value);
            if ($value === []) {
                unset($data[$key]);
            } else {
                $data[$key] = $value;
            }
        }
    }
    return $isList ? array_values($data) : $data;
}

function canonical($value) {
    if (!is_array($value)) {
        return $value;
    }
    $value = array_map('canonical', $value);
    if (!array_is_list($value)) {
        ksort($value);
    }
    return $value;
}

/**
 * A file that exists but is not a JSON object exits with $errorCode, before
 * the output is written: treating it as empty would resolve without the
 * operator's packages and remove them from vendor/.
 */
function readJson(string $path, int $errorCode = 1): ?array {
    if (!is_file($path)) {
        return null;
    }
    $text = file_get_contents($path);
    $object = $text === false ? null : json_decode($text);
    if (!is_object($object)) {
        $error = $text === false ? 'cannot be read'
            : (json_last_error() !== JSON_ERROR_NONE ? json_last_error_msg() : 'not a JSON object');
        fwrite(STDERR, "ERROR: $path: $error\n");
        exit($errorCode);
    }
    return json_decode($text, true);
}

function stringList($value): array {
    return is_array($value) ? array_values(array_filter($value, 'is_string')) : [];
}

/**
 * Files an include pattern matches, keyed by their path as written in
 * composer.local.json (relative to MW_HOME unless the pattern is absolute).
 */
function matchInclude(string $mwHome, string $pattern): array {
    $absolute = str_starts_with($pattern, '/');
    $matches = [];
    foreach (glob($absolute ? $pattern : "$mwHome/$pattern") ?: [] as $file) {
        if (is_file($file)) {
            $matches[$absolute ? $file : substr($file, strlen($mwHome) + 1)] = $file;
        }
    }
    return $matches;
}

function isOperatorFile(string $mwHome, string $file): bool {
    $real = realpath($file);
    if ($real === false) {
        return false;
    }
    foreach (['user-extensions', 'user-skins'] as $dir) {
        $root = realpath("$mwHome/$dir");
        if ($root !== false && str_starts_with($real, "$root/")) {
            return true;
        }
    }
    $home = realpath($mwHome);
    return $home === false || !str_starts_with($real, "$home/");
}
