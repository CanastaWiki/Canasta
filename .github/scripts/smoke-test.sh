#!/bin/bash
# Boot an image the way `canasta create` does: start it beside MariaDB,
# install a wiki with install.php, then recreate the container. Fails unless
# each container reaches healthy, the startup skips composer, and the wiki
# serves its main page.
#
# Usage: smoke-test.sh <image>

set -euo pipefail

image=$1
name=canasta-smoke-$$
work=$(mktemp -d)
db_password=$(openssl rand -hex 16)
admin_password=$(openssl rand -hex 16)
sitename="Smoke Test"

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    echo "::group::web container log"
    docker logs "$name-web" 2>&1 | tail -n 400 || true
    echo "::endgroup::"
  fi
  docker rm -f "$name-web" "$name-db" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "::error::$image: $*"
  exit 1
}

# Wait until the web container's healthcheck passes, failing early if it
# exits.
wait_healthy() {
  local state
  for _ in $(seq 1 90); do
    state=$(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "$name-web")
    case "$state" in
      "running healthy") return 0 ;;
      running*) sleep 5 ;;
      *) fail "web container is $state" ;;
    esac
  done
  fail "web container did not become healthy: $state"
}

start_web() {
  # The healthcheck's own command at a shorter interval.
  docker run -d --name "$name-web" --network "$name" \
    --health-interval 10s \
    -e MW_SITE_SERVER=http://localhost \
    -e MW_SECRET_KEY="$(openssl rand -hex 32)" \
    -e MYSQL_HOST=db \
    -e MYSQL_USER=root \
    -e MYSQL_PASSWORD="$db_password" \
    -e CANASTA_ENABLE_VARNISH=false \
    -v "$work/extensions:/var/www/mediawiki/w/user-extensions" \
    -v "$work/skins:/var/www/mediawiki/w/user-skins" \
    -v "$work/config:/mediawiki/config" \
    -v "$work/images:/mediawiki/images" \
    "$image" >/dev/null
  wait_healthy
  # grep without -q reads all of the log, so pipefail sees no SIGPIPE.
  docker logs "$name-web" 2>&1 | grep 'Composer dependencies unchanged' >/dev/null \
    || fail "startup ran composer without operator content"
}

docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"

mkdir -p "$work"/{config,extensions,skins,images}
cat > "$work/config/wikis.yaml" <<EOF
wikis:
- id: main
  url: localhost
  name: $sitename
EOF

docker network create "$name" >/dev/null
docker run -d --name "$name-db" --network "$name" --network-alias db \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' \
  --health-interval 2s \
  -e MYSQL_ROOT_HOST=% \
  -e MYSQL_ROOT_PASSWORD="$db_password" \
  docker.io/library/mariadb:11.4 >/dev/null

start_web
echo "$image: first start is healthy"

# install.php as the CLI runs it, with its LocalSettings.php discarded.
docker exec -i "$name-web" bash -c \
  'umask 077 && mkdir -p /tmp/canasta-install && IFS= read -r p && printf %s "$p" > /tmp/canasta-install/.dbpass && IFS= read -r p && printf %s "$p" > /tmp/canasta-install/.pass' \
  <<< "$db_password"$'\n'"$admin_password"
docker exec "$name-web" env -u MW_SECRET_KEY php maintenance/install.php \
  --dbpassfile=/tmp/canasta-install/.dbpass \
  --passfile=/tmp/canasta-install/.pass \
  --dbserver=db:3306 --dbname=main --dbuser=root \
  --confpath=/tmp/canasta-install/ --scriptpath=/w --server=http://localhost \
  main Admin
docker rm -f "$name-web" >/dev/null

start_web
echo "$image: start after install is healthy"

page=$(docker exec "$name-web" wget -qO- --header 'Host: localhost' \
  http://127.0.0.1/wiki/Main_Page) || fail "the main page did not load"
grep -q "$sitename</title>" <<< "$page" || fail "the main page is not the wiki's"
echo "$image: main page served"
