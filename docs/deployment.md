# Deployment and runtime configuration

## Baking vs enabling extensions

| Layer | Mechanism | Where |
|-------|-----------|--------|
| **Bake into image** | [values.yml](../values.yml) → gomplate build | This repository |
| **Enable on a wiki** | `wfLoadExtension()` in `LocalSettings.php` | Wiki deployment configuration |
| **Legacy env enable** | `MW_LOAD_EXTENSIONS` intersected with `DOCKER_EXTENSIONS` | Deprecated; use [values.yml](../values.yml) and per-wiki `LocalSettings.php` instead |

Adding an extension to [values.yml](../values.yml) puts files in the image. It does **not** enable the extension on any wiki. Enable it per wiki by adding `wfLoadExtension()` (and any required config) to that wiki's `LocalSettings.php` or equivalent deployment configuration.

The `DOCKER_EXTENSIONS` constant in [_sources/canasta/DockerSettings.php](../_sources/canasta/DockerSettings.php) is a legacy allowlist for `MW_LOAD_EXTENSIONS`. It is not updated by [values.yml](../values.yml) today. New work should use `LocalSettings.php`; the env-based path may be removed in a future cleanup.

## Environment variables

Taqasta reads many settings from environment variables (admin account, database, site URL, uploads, email, etc.). See [docker-compose.sample.yml](../docker-compose.sample.yml) for examples.

CI and local e2e stacks use [.env.ci](../.env.ci). Copy it to `.env` before running `docker compose` (see [e2e/README.md](../e2e/README.md)).

### Non-prod visual indicator

Set `MW_SHOW_NON_PROD_INDICATOR` to `true` to show a red frame and a NOT PRODUCTION label on every page. The default value is off.

You can also set `$wgWikiTeqNonProdIndicator` to `true` in the site `LocalSettings.php` file. Do not enable this on a production wiki.

Click the label to hide the frame and the label for 20 seconds on the current page. A new page load shows the overlay again.

## Compose and Kubernetes templates

| Path | Purpose |
|------|---------|
| [docker-compose.yml](../docker-compose.yml) | CI / E2E stack (not for production use as-is) |
| [docker-compose.sample.yml](../docker-compose.sample.yml) | Local development reference |
| [main/kubernetes/](../main/kubernetes/) | Example Kubernetes manifests (wiki, runjobs, mysql, …) |

## `.htaccess` overrides

The image ships a default `.htaccess` at `/var/www/mediawiki/.htaccess`.

- **Replace entirely:** mount to `/var/www/mediawiki/.htaccess`
- **Override wiki rules only:** mount to `/var/www/mediawiki/w/.htaccess`

Example docker-compose configuration:

```yaml
volumes:
  # Replace entire file at DocumentRoot
  - ./my-custom-htaccess:/var/www/mediawiki/.htaccess
  # OR override wiki subdirectory only (preserves base config)
  - ./my-custom-htaccess:/var/www/mediawiki/w/.htaccess
```

Test custom rules after image upgrades.

## Image tags

GitHub Actions assigns tags when building images:

| Build type | Tag format | Example |
|------------|------------|---------|
| **PR** (testing) | `MW_CORE_VERSION-YYYYMMDD-<PR_NUMBER>` | `1.43.8-20260717-405` |
| **master** (production) | `latest` | `latest` |
| **master** (production) | `VERSION` (from [VERSION](../VERSION)) | `1.3.1-pre` |
| **master** (production) | `MW_MAJOR_VERSION-latest` | `1.43-latest` |
| **master** (production) | `MW_CORE_VERSION-latest` | `1.43.8-latest` |
| **master** (production) | `MW_CORE_VERSION-YYYYMMDD-<short-sha>` | `1.43.8-20260717-d562a4b` |

Use PR tags for testing; use tags from `master` or the applicable LTS maintenance branch for production deployments.

## Profiling

See [README profiling section](../README.md#profiling) for xhprof setup (`MW_PROFILE_SECRET`, `forceprofile` parameter, and profiler settings).
