#!/bin/bash

# Unified composer autoloader
#
# The image builds vendor/ from $MW_HOME/composer.canasta.json, the merge-plugin
# includes of the bundled extensions and skins that have Composer
# dependencies. config/composer.local.json holds only the operator's
# additions: require, repositories, includes for user extensions and skins,
# and extra.canasta.exclude-bundled. composer-local.php merges the two into
# $MW_HOME/composer.local.json and hashes the operator content; composer runs
# only when that hash differs from the one vendor/ was built for, so with no
# operator content the build-time vendor/ is used as-is.
#
# The hash file lives at $MW_HOME/.composer-deps-hash, INSIDE the
# container (not on the bind-mounted $MW_VOLUME). This is intentional:
# vendor/ is also intra-container, so the hash and the deps it
# describes share the same lifetime. When the container is recreated,
# both go away together and composer correctly re-runs. Storing the
# hash on $MW_VOLUME would survive container recreates but vendor/
# would not, causing the post-recreate start to skip composer with a
# matching hash and a missing vendor (issue #141).
#
# A failed update is recorded in config/persistent/composer-update.failed for
# the CLI to report; the file is removed once vendor/ matches again.

COMPOSER_LOCAL="$MW_VOLUME/config/composer.local.json"
COMPOSER_CANASTA="$MW_HOME/composer.canasta.json"
COMPOSER_HASH_FILE="$MW_HOME/.composer-deps-hash"
COMPOSER_FAILED="$MW_VOLUME/config/persistent/composer-update.failed"

write_failed() {
  mkdir -p "$(dirname "$COMPOSER_FAILED")"
  {
    echo "Composer update failed at $(date -u +%Y-%m-%dT%H:%M:%SZ) (exit $1)."
    cat
  } > "$COMPOSER_FAILED"
}

COMPOSER_LOCAL_ERRORS=$(mktemp)
CURRENT_HASH=$(php "$MW_HOME/maintenance/composer-local.php" \
    "$MW_HOME" "$COMPOSER_CANASTA" "$COMPOSER_LOCAL" "$MW_HOME/composer.local.json" \
    2>"$COMPOSER_LOCAL_ERRORS")
status=$?
cat "$COMPOSER_LOCAL_ERRORS" >&2
if [ "$status" -ne 0 ]; then
  if [ "$status" -eq 3 ]; then
    reason="config/composer.local.json could not be parsed; composer was not run."
  else
    reason="composer.local.json could not be generated; composer was not run."
  fi
  echo "$reason" >&2
  { echo "$reason"; echo; cat "$COMPOSER_LOCAL_ERRORS"; } | write_failed "$status"
  rm -f "$COMPOSER_LOCAL_ERRORS"
  exit "$status"
fi
rm -f "$COMPOSER_LOCAL_ERRORS"

SAVED_HASH=""
if [ -f "$COMPOSER_HASH_FILE" ]; then
  SAVED_HASH=$(tr -d '[:space:]' < "$COMPOSER_HASH_FILE")
fi
if [ "$CURRENT_HASH" = "$SAVED_HASH" ]; then
  echo "Composer dependencies unchanged, skipping update."
  rm -f "$COMPOSER_FAILED"
  exit 0
fi

echo "Composer dependencies changed, running composer update..."
COMPOSER_OUTPUT=$(mktemp)
composer update --working-dir="$MW_HOME" --no-dev --no-interaction 2>&1 | tee "$COMPOSER_OUTPUT"
status=${PIPESTATUS[0]}
# composer can exit 0 having removed packages a bundled extension needs, so
# check vendor/ against the effective list too.
if [ "$status" -eq 0 ] && [ -f "$MW_HOME/maintenance/verify-composer-deps.php" ]; then
  php "$MW_HOME/maintenance/verify-composer-deps.php" "$MW_HOME" 2>&1 | tee -a "$COMPOSER_OUTPUT"
  status=${PIPESTATUS[0]}
fi

# Only record the new hash if the update succeeded. A failed update may have
# changed vendor/ already, so drop the saved hash too: otherwise reverting to
# the previous content would match it and skip composer.
if [ "$status" -eq 0 ]; then
  echo "$CURRENT_HASH" > "$COMPOSER_HASH_FILE"
  rm -f "$COMPOSER_FAILED"
else
  rm -f "$COMPOSER_HASH_FILE"
  echo "composer update failed; removing the dependency hash so it retries on next start." >&2
  {
    echo "Includes:"
    php -r '
      $data = json_decode(file_get_contents($argv[1]), true);
      foreach ($data["extra"]["merge-plugin"]["include"] ?? [] as $include) {
        echo "  $include\n";
      }
    ' "$MW_HOME/composer.local.json"
    echo
    tail -n 200 "$COMPOSER_OUTPUT"
  } | write_failed "$status"
fi
rm -f "$COMPOSER_OUTPUT"
exit "$status"
