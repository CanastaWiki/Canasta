# Canasta
Canasta is a full-featured MediaWiki stack for easy deployment of enterprise-ready MediaWiki on production environments. It is "A comfy home for your data"!

This repository is just one of the repositories for the Canasta distribution, and arguably not the main one (that would be [CanastaBase](https://github.com/CanastaWiki/CanastaBase), the base layer for this Canasta repository, and the one that holds MediaWiki and all its dependencies). This Canasta repository adds on to CanastaBase a set of over 170 extensions and skins.

For more information on Canasta, for both users and developers, see the Canasta homepage at https://canasta.wiki/.

## Generating Sitemaps

Canasta includes built-in support for generating XML sitemaps for search engines. To enable automatic sitemap generation, add this environment variable to your `docker-compose.yml`:

```yaml
environment:
  MW_ENABLE_SITEMAP_GENERATOR: "true"
```

Optional configuration:

```yaml
environment:
  MW_ENABLE_SITEMAP_GENERATOR: "true"
  MW_SITEMAP_PAUSE_DAYS: "7"         # Days between regeneration (default: 7)
  MW_SITEMAP_IDENTIFIER: "mediawiki" # Identifier in sitemap filename (default: mediawiki)
  MW_SITEMAP_SUBDIR: ""              # Subdirectory within /sitemap/ (default: empty)
```

After enabling, sitemaps will be automatically generated and accessible at:
- **Sitemap index:** `https://your-wiki.com/w/sitemap/sitemap-index-{identifier}.xml`
- **Individual sitemaps:** `https://your-wiki.com/w/sitemap/sitemap-{identifier}-NS_0-0.xml.gz`

The sitemap generator runs automatically in the background and regenerates sitemaps based on `MW_SITEMAP_PAUSE_DAYS`.
