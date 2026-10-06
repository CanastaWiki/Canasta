# Extension lifecycle

[Taqasta](https://github.com/WikiTeq/Taqasta) is a docker image that contains many extensions pre-installed and available for use. Extensions are added in two different ways — by cloning the git repo, or by loading the extension via composer.

Extensions, skins, and Composer packages are defined in [values.yml](../values.yml). See [build-system.md](build-system.md) for how the build system uses that file.

Create a branch, make your changes, and open a pull request. The steps below cover editing [values.yml](../values.yml) and validating the build.

After an extension is in the image, enable it on a specific wiki via that wiki's `LocalSettings.php` (or equivalent deployment configuration). See [deployment.md](deployment.md).

## Adding

### Git

Update [values.yml](../values.yml) to include the desired extension under the `extensions` section. Be sure to include a commit reference — we pin extensions to specific commits so that rebuilding the docker image does not accidentally change the version of the extension.

- A `commit` is required unless `gerrit_ref` is set (Gerrit clones use the ref instead of a commit hash)
- If the repo is not specified, the extension is cloned from GitHub (`https://github.com/wikimedia/mediawiki-extensions-<Name>`) unless `gerrit_ref` is set, in which case it is cloned from Gerrit
- If the branch is not specified, the branch corresponding to the release of MediaWiki is assumed (e.g. REL1_43), but there is no harm in explicitly recording that branch
- If possible, add the Wikidata ID for the extension

Example patch: [Add extension via git](https://github.com/WikiTeq/Taqasta/commit/4ad0eb06aba188905657c29b01856db4edc4e0a0)

If the extension has composer dependencies that are required, make sure to include `additional steps: [composer update]` in the extension's entry. See [extension with composer update step](https://github.com/WikiTeq/Taqasta/commit/c2ecdf13538b60288ca2016fc87fe7484832de02).

```yaml
  - MarkdownPages:
      repository: https://github.com/WikiTeq/mediawiki-extension-MarkdownPages.git
      branch: master
      commit: e7b4c1a320943797fcacfa94f2eef1d428419cea
      additional steps:
        - composer update
```

### Composer

Update [values.yml](../values.yml) to include the desired extension's package under the `packages` section. Be sure to specify a specific version of the extension package to load — we pin extensions to specific commits/versions so that rebuilding the docker image does not accidentally change the version of the extension.

Example patch: [composer package addition](https://github.com/WikiTeq/Taqasta/commit/72761f290506bd3c6630f25ed2c8e0a2c6cb5b0e).

### Validate and compile

Note: these two steps are optional and just serve to confirm that you modified the values correctly.

For Windows users with the Git Bash terminal, set `MSYS_NO_PATHCONV=1` before running these commands if path conversion causes errors.

```bash
./validate.sh
```

This checks that your YAML is valid against the schema.

```bash
./compile.sh
```

This generates the final `Dockerfile` and composer files from templates.

### Image testing

After pushing your changes to a PR:

- The CI/CD pipeline will build the new image
- Check GitHub Actions for build status
- Once built, note the new image tag

Use this new image tag to test that the extension works properly, and then get your PR merged. At this point, the extension is now available in the base image, but it will **NOT** be automatically enabled for any wikis. To enable it for a specific wiki, add `wfLoadExtension()` (and any required config) to that wiki's `LocalSettings.php`. Make sure that the wiki uses a version of the image that includes the extension.

You can use the image tag from the PR for testing; only images built from merged PRs on `master` or the applicable LTS maintenance branch should be used in production.

## Updating

Extensions are added in two different ways — by cloning the git repo, or by loading the extension via composer. Depending on how the extension was added, how it gets updated is different.

Locate the extension's entry in [values.yml](../values.yml), under either `extensions` (if installed with git) or `packages` (if installed with composer).

Update the commit (for extensions from git) or package version (for extensions from composer) to the new version.

Example patches:

- [Git extension bump](https://github.com/WikiTeq/Taqasta/commit/f4bec26588c07ceac1bb1d6ddfae910500253a70)
- [Composer extension bump](https://github.com/WikiTeq/Taqasta/commit/fd146ed32d72ad9337248532d59db0dcc7644d55)

For extensions installed with git, if a new version of an extension now has composer dependencies and previously did not, or the other way around, update the `additional steps` section of the extension details to load composer dependencies.

Example patch: [add/remove composer update step](https://github.com/WikiTeq/Taqasta/commit/f36047605d6bf84a22626af424f5c0b0f597a11a).

If there were any patches that were applied within Taqasta, determine if they are still needed. If they are, update them; if not, remove them entirely. See [patching.md](patching.md).

## Removing

Extensions are added in two different ways — by cloning the git repo, or by loading the extension via composer. Depending on how the extension was added, how it gets removed is different.

Remove the extension's entry from [values.yml](../values.yml). It will be under either `extensions` (if loaded with git), or `packages` (if loaded with composer).

Do **not** edit the generated `Dockerfile` or [_sources/configs/composer.wikiteq.json](../_sources/configs/composer.wikiteq.json) directly. [compile.sh](../compile.sh) regenerates both from [values.yml](../values.yml) and templates (see [build-system.md](build-system.md)). Removing the extension also drops any `additional steps: composer update` merge-plugin entry for that extension.

If the extension had Taqasta-specific patches, remove the matching `patches:` entry from [values.yml](../values.yml) and delete the patch file from [_sources/patches/](../_sources/patches/). See [patching.md](patching.md).

If the extension was the only consumer of a custom Composer repository listed under `repositories:` in [values.yml](../values.yml), remove that repository entry as well.

Example patches:

- [remove extension](https://github.com/WikiTeq/Taqasta/commit/42b7cf2fc0c0fad6830789c314882520230170c5)
- [remove extension with patch](https://github.com/WikiTeq/Taqasta/commit/1c58a664045232afb7b2c1600dd47f65232582c)

Extension availability in the image is driven by [values.yml](../values.yml). For the legacy env path, the `DOCKER_EXTENSIONS` list in [DockerSettings.php](../_sources/canasta/DockerSettings.php) may still need updating until that path is cleaned up (see [deployment.md](deployment.md)). Wikis that still reference the extension need it removed from their `LocalSettings.php` separately.
