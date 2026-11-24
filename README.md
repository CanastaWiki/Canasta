# Canasta
Canasta is a full-featured MediaWiki stack for easy deployment of enterprise-ready MediaWiki on production environments. It is "A comfy home for your knowledge"!

This repository builds two Docker images with the same version number:
- `canasta-base`, from the top-level `Dockerfile`: MediaWiki core and the extensions and skins bundled with it, PHP and Apache on Debian, and Canasta's startup, maintenance and configuration scripts. Other Canasta-like MediaWiki distributions can use it as a base image and add their own extensions, skins and tools.
- `canasta`, from `Dockerfile.canasta`: `canasta-base` plus more than 170 extensions and skins, chosen and pinned in `extensions-skins.yaml` through [Recommended Revisions](https://github.com/CanastaWiki/RecommendedRevisions).

For more information on Canasta, for both users and developers, see the Canasta homepage at https://canasta.wiki/.
