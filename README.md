# Canasta MediaWiki docker image

# Quick setup

* Clone the repository
* Navigate to the repo directory and run `docker-compose up -d`
* Navigate to `http://localhost` and run wiki setup wizard:
  * Database host: `db`
  * Database user: `root`
  * Database password: `medaiwiki` (by default, see `Configuration` section)
* Save generated `LocalSettings.php` to the `config` directory
* Visit your wiki at `http://localhost`

# Configuration

You can change some options by editing the `.env` file, see `.env.example` for details:

* `PORT` - modify the apache port, default is `80`
* `MYSQL_PASSWORD` - modify MySQL container `root` user password, default is `mediawiki`
(use it when installing the wiki via wizard)
* `PHP_UPLOAD_MAX_FILESIZE` - php.ini upload max file size
* `PHP_POST_MAX_SIZE` - php.ini post max size

You can add/modify extensions and skins using the following mount points:

* `./config` - persistent bind-mount which stores the `LocalSettings.php` file,
volumed in as `mediawiki/config/LocalSettings.php -> /var/www/mediawiki/w/LocalSettings.php`
* `./images` - persistent bind-mount which stores the wiki images,
volumed in as `mediawiki/images -> /var/www/mediawiki/w/images`
* `./skins` - persistent bind-mount which stores 3rd party skins,
volumed in as `/var/www/mediawiki/w/skins`
* `./extensions` - persistent bind-mount which stores 3rd party extensions,
volumed in as `/var/www/mediawiki/w/extensions`
* `./_initdb` - persistent bind-mount which can be used to initialize the database container
with a mysql dump. You can place `.sql` or `.gz` database dump there. This is optional and
intended to be used for migrations only.

# Enabling extensions

On the `LocalSettings.php` you'll find a full list of extensions bundled with the image,
remove the `#` comment symbol near the extension to enable it, eg:

```php
#cfLoadExtension('Cite');
```

```php
cfLoadExtension('Cite');
```

# Enabling skins

On the `LocalSettings.php` you'll find a full list of skins bundled with the image,
remove the `#` comment symbol near the skin to enable it, eg:

```php
#cfLoadSkin('Vector');
```

```php
cfLoadSkin('Vector');
```

# Installing 3rd party extension

In order to install a 3rd party extension simply place it under the `./extensions`
directory and add `cfLoadExtension` call to the bottom of `./config/LocalSettings.php`, eg:

```php
cfLoadExtension('MyCustomExtension');
```

# Installing 3rd party skins

In order to install a 3rd party skin simply place it under the `./skins`
directory and add `cfLoadSkin` call to the bottom of `./config/LocalSettings.php`, eg:

```php
cfLoadSkin('MyCustomSkin');
```

# Database

By default, the stack uses `mysql:8.0` container for database and stores MySQL
files under `mysql-data-volume` to make the database persist across container
restarts.

It's not necessary to use the volume and the database container, you can switch
to any external database server you wish by simply modifying the following values
under your `./config/LocalSettings.php` file (or by specifying your DB server during setup wizard):

```php
## Database settings
$wgDBserver = "my.custom.mysql.server.com";
$wgDBname = "customdatabasename";
$wgDBuser = "customuser";
$wgDBpassword = "custompassword";
```

If you switch to external database server feel free to remove the mysql service from
the `docker-compose.yml` file:

```yml
services:
  db: # <- remove whole branch
    ...
  web:
    ...
    links: # <- remove whole branch
      - db
    depends_on: # <- remove whole branch
      - db
```

## Backing up database

To create a database backup use the following command:

```bash
cd ~/path/to/canasta
docker-compose exec db /bin/bash \
  -c 'mysqldump $MYSQL_DATABASE -uroot -p"$MYSQL_ROOT_PASSWORD" 2>/dev/null | gzip | base64 -w 0' \
  | base64 -d \
  > backup_$(date +"%Y%m%d_%H%M%S").sql.gz
```

This will create `~/path/to/canasta/backup_<DATE>.sql.gz` file with a database backup

## Deleting the database volume

If you need to start over or prune the database data use the command below:

```bash
cd ~/path/to/canasta
docker-compose down --volumes
```

This will stop all the services and remove all the linked persistent volumes.

# Executing maintenance scripts

The image is bundled with automatic job-runner, transcoder and log-rotator, but
if you need to run any other maintenance script you can do it using this command:

```bash
cd ~/path/to/canasta
docker-compose exec web php maintenance/rebuildall.php
```

The image also configured to automatically run the `update.php` script on
start, so if you enable some schema affecting extensions like `SemanticMediawiki` you
may need to restart the stack via `docker-compose restart` or, alternatively run the
`update.php` script by yourself via:

```bash
cd ~/path/to/canasta
docker-compose exec web php maintenance/update.php --quick
```

# Elasticsearch

By default, the stack uses `elasticsearch/elasticsearch:6.8.13` container and stores
indexes under `elasticsearch` volume to make the data persist across container
restarts.

Despite the ElasticSearch container is active by default the wiki won't use it
until you'll make necessary configurations in `LocalSettings.php`, eg:

```php
cfLoadExtension( 'Elastica' );
cfLoadExtension( 'CirrusSearch' );
$wgCirrusSearchServers = [ 'elasticsearch' ];
// or:
$wgCirrusSearchClusters = [
        'default' => [ 'elasticsearch' ],
];
```

and follow initialization instructions, see https://github.com/wikimedia/mediawiki-extensions-CirrusSearch/blob/master/README and
see more details at https://www.mediawiki.org/wiki/Extension:CirrusSearch

# Sitemap

The image in bundled with sitemap auto-generation script which stores the resulting
sitemap to volume `sitemap` and symlinks into `/var/www/mediawiki/w/sitemap`

# Kubernetes

Configs are located at `kubernetes` directory composed as a file per
service (web, db, elasticsearch). The simplest way to run it is as below (make sure you
have a node configured or `minikube` for development environment):

```bash
minikube start
cd ~/path/to/canasta
kubectl apply -f kubernetes
minikube service web
```

The mount-bind directories are created at `/opt/mediawiki` root ( you can change this by
modifying the conf files). If nothing exists at the given path, an empty directory will 
be created there as needed with permission set to 0755, having the same group and ownership 
with Kubelet . Make sure the `/opt/mediawiki/elasticsearch` and `/opt/mediawiki/images`,
`/opt/mediawiki/sitemap` are writable.

Note, the kubernetes stack provided (same as the compose stack) does not include any
front-end load balancer or proxy web server, so it's up to you to route the requests to the
wiki pod/container.

Note, the kubernetes stack provided relies on the [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
volume binding hence not intended to be used as a scalable solution (>1 pod per deployment) and
for some in-cloud Kubernetes deployments.

It's recommended to replace `hostPath` mounts with [PersistentVolume](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)s
 using [StorageClass](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).
