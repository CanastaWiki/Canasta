# Canasta
A full-featured MediaWiki stack for easy deployment of enterprise-ready MediaWiki on production environments.

This repo is for the MediaWiki application Docker image included in the Canasta stack.

Canasta is built on the following principles:

- **Beginner friendly**. Canasta should be easy for a sysadmin to set up and configure.
- **Ease of installation and upgradability**. Canasta bundles everything needed to run MediaWiki and updating MediaWiki is as simple as pulling a new version of Canasta.
- **Ease of maintainability**. Canasta takes care of all of the routine maintenance aspects of MediaWiki without any further installations needed.
- **Convenience**. Canasta should have enhancements to allow for an easy-to-use administration experience. For example, Canasta bundles commonly-used extensions and skins used in the Enterprise MediaWiki community. In the future, Canasta aims to add support for enhanced capabilities to manage a MediaWiki instance, such as a Canasta wiki manager.
- **As backwards compatible with vanilla MediaWiki as possible**. Canasta should support drag-and-drop of a “normal” MediaWiki installation’s LocalSettings.php configuration. Sysadmins should be able to make most customizations just as they would with a “normal” install of MediaWiki, without referring to Canasta-specific documentation.
- **Stability**. Canasta will use an “ltsrel” compatibility policy. It will be kept up-to-date with the latest Long Term Support versions of MediaWiki and ignore intermediate versions. Canasta will be updated for all LTS minor releases. Extensions will be tied to specific git commits and will be updated infrequently.
- **Open source**. Canasta and its source code are free to be used and modified by everyone.
- **Customizability**. Sysadmins can use as little or as much of Canasta as you want by choosing which features to enable in their LocalSettings.php.
- **Extensibility**. Canasta should support “after-market” customization of the Canasta image. Derivative images should be able to make any change they want to Canasta, including overriding its base functionality.
- **Ready for source control**. Storing configuration on source control is an excellent DevOps practice for many reasons, including the ease of separating functionality from configuration and data. Canasta is built with this in mind. Simply follow Canasta’s “stack” repo structure and you’ll be able to place your Canasta config into source control.

Canasta supports two orchestrators for managing the stack: Docker Compose and Kubernetes.

# Setup

## Quick setup
### Import existing wiki
* Clone the stack repository
* Copy `.env.example` to `.env` and customize as needed
* Drop your database dump (in either a `.sql` or `.sql.gz` file) into the `_initdb/` directory
* Place your existing `LocalSettings.php` in the `config/` directory and change your database configuration to be the following
  * Database host: `db`
  * Database user: `root`
  * Database password: `mediawiki` (by default; see `Configuration` section)
* Navigate to the repo directory and run `docker-compose up -d`
* Visit your wiki at `http://localhost`

### Create new wiki
* Clone the stack repository
* Copy `.env.example` to `.env` and customize as needed
* Navigate to the repo directory and run `docker-compose up -d`
* Navigate to `http://localhost` and run wiki setup wizard:
  * Database host: `db`
  * Database user: `root`
  * Database password: `mediawiki` (by default; see `Configuration` section)
* Place your new `LocalSettings.php` in the `config/` directory
* Run `docker-compose down`, then `docker-compose up -d` (this is important because it initializes your `LocalSettings.php` for Canasta)
* Visit your wiki at `http://localhost`

## Configuration
Canasta relies on setting environment variables in the Docker container for controlling
aspects of the system that are outside the purview of LocalSettings.php. You can change
these options by editing the `.env` file; see `.env.example` for details:

* `PORT` - modify the publicly-accessible HTTP port, default is `80`
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

## Enabling extensions
In `LocalSettings.php` you will find a full list of extensions bundled with the image;
remove the `#` comment symbol near an extension to enable it, e.g.:

```php
#cfLoadExtension( 'Cite' );
```

```php
cfLoadExtension( 'Cite' );
```

## Enabling skins
In `LocalSettings.php` you will find a full list of skins bundled with the image;
remove the `#` comment symbol near a skin to enable it, e.g.:

```php
#cfLoadSkin( 'Timeless' );
```

```php
cfLoadSkin( 'Timeless' );
```

## Installing 3rd party extensions
In order to install a 3rd party extension, simply place it in the `./extensions`
directory and add a `wfLoadExtension` call to `./config/LocalSettings.php`, e.g.:

```php
wfLoadExtension( 'MyCustomExtension' );
```

## Installing 3rd party skins
In order to install a 3rd party skin, simply place it in the `./skins`
directory and add a `wfLoadSkin` call to `./config/LocalSettings.php`, e.g.:

```php
wfLoadSkin( 'MyCustomSkin' );
```

# Components
Supporting components of Canasta are not located directly in the Canasta image, but are part of the Canasta stack.
They are invoked on the `docker-compose.yml` file for Docker Compose installations
or the Kubernetes deployment manifest for Kubernetes installations.

Instructions below on handling the components are for Docker Compose only.
For Kubernetes information, please see the Kubernetes section below.

## Database
By default, the stack uses the `mysql:8.0` container for the database and stores MySQL
files in `mysql-data-volume` to make the database persist across container
restarts.

It is not necessary to use the volume and the database container. You can switch
to any external database server you wish by simply modifying the following values
under your `./config/LocalSettings.php` file (or by specifying your DB server during setup wizard):

```php
## Database settings
$wgDBserver = "my.custom.mysql.server.com";
$wgDBname = "customdatabasename";
$wgDBuser = "customuser";
$wgDBpassword = "custompassword";
```

If you switch to an external database server, feel free to remove the `mysql` service from
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

### Backing up the database

To create a database backup, use the following command:

```bash
cd ~/path/to/canasta
docker-compose exec db /bin/bash \
  -c 'mysqldump $MYSQL_DATABASE -uroot -p"$MYSQL_ROOT_PASSWORD" 2>/dev/null | gzip | base64 -w 0' \
  | base64 -d \
  > backup_$(date +"%Y%m%d_%H%M%S").sql.gz
```

This will create `~/path/to/canasta/backup_<DATE>.sql.gz` file with a database backup.

### Deleting the database volume

If you need to start over or prune the database data, use the command below:

```bash
cd ~/path/to/canasta
docker-compose down --volumes
```

This will stop all the services and remove all the linked persistent volumes.

## Executing maintenance scripts

The image is bundled with automatic job-runner, transcoder and log-rotator scripts, but
if you need to run any other maintenance script you can do so using this command:

```bash
cd ~/path/to/canasta
docker-compose exec web php maintenance/rebuildall.php
```

The image is also configured to automatically run the `update.php` script on
start, so if you enable some extension that adds its own database tables (like `Semantic Mediawiki`),
you can add the DB tables by either restarting the stack via `docker-compose restart, or just running the
`update.php` script like so:

```bash
cd ~/path/to/canasta
docker-compose exec web php maintenance/update.php --quick
```

## Elasticsearch

By default, the stack uses the `elasticsearch/elasticsearch:6.8.13` container and stores
indexes in the `elasticsearch` volume, to make the data persist across container
restarts.

Despite the fact that the Elasticsearch container is active by default, the wiki won't use it
until you make the necessary configuration changes in `LocalSettings.php`, e.g.:

```php
cfLoadExtension( 'Elastica' );
cfLoadExtension( 'CirrusSearch' );
$wgCirrusSearchServers = [ 'elasticsearch' ];
// or:
$wgCirrusSearchClusters = [
        'default' => [ 'elasticsearch' ],
];
```

Then, follow the initialization instructions; see https://github.com/wikimedia/mediawiki-extensions-CirrusSearch/blob/master/README and
https://www.mediawiki.org/wiki/Extension:CirrusSearch.

## Sitemap

The image includes a sitemap auto-generation script, which stores the resulting
sitemap to the volume `sitemap`, which is symlinked to `/var/www/mediawiki/w/sitemap`.

# Kubernetes
Canasta offers Kubernetes support for heavy-duty wikis needing the power provided by Kubernetes.
However, it is not for the faint of heart. We recommend smaller wikis use Docker Compose to manage their stack.

Configs are located in the `kubernetes` directory, organized with each file representing a
service (`web`, `db`, `elasticsearch`). The simplest way to run it is as below (make sure you
have a node configured or `minikube` for a development environment):

```bash
minikube start
cd ~/path/to/canasta
kubectl apply -f kubernetes
minikube service web
```

You will want to use `kubeadm` or other Kubernetes implementations for your production environment.
We aim to provide documentation on how to do this in the future.

The mount-bind directories are created at `/opt/mediawiki` root (you can change this by
modifying the conf files). If nothing exists at the given path, an empty directory will 
be created there as needed with permission set to 0755, having the same group and ownership 
as Kubelet. Make sure the `/opt/mediawiki/elasticsearch`, `/opt/mediawiki/images` and
`/opt/mediawiki/sitemap` directories are writable.

Note that the Kubernetes stack provided (same as the Docker Compose stack) does not include any
front-end load balancer or proxy web server, so it's up to you to route the requests to the
wiki pod/container.

Note that the Kubernetes stack provided relies on the [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
volume binding, so it's not intended to be used as a scalable solution (>1 pod per deployment) and
for some in-cloud Kubernetes deployments.

It is recommended to replace `hostPath` mounts with [PersistentVolume](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)s
 using [StorageClass](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).
 
 
# More info
## History
Project Canasta was launched by Yaron Koren, head of WikiWorks. Project Canasta is intended to make
Enterprise MediaWiki administration easier, while bringing the full power of MediaWiki and its extensions to the table.

## What's behind the name?
Canasta means "basket" in Spanish, alluding to Canasta's full-featured stack being like a single basket, complete with all of the tools needed.
