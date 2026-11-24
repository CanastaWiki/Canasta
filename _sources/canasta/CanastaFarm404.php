<?php
/**
 * CanastaFarm404.php — styled 404 page and wiki directory for Canasta wiki farms.
 *
 * Loaded by FarmConfigLoader.php in two modes:
 *   - 404 mode ($directoryOnly = false): shows error box + optional wiki directory
 *   - Directory mode ($directoryOnly = true): shows wiki directory as a landing page
 *
 * Variables in scope from the caller: $wikiConfigurations, $urlComponents, $path,
 * $directoryOnly.
 *
 * Wiki logos are resolved server-side from public_assets/<wiki_id>/logo.<ext>,
 * which the web server grants anonymously regardless of the wiki's read
 * permissions. Wikis without such a file fall back to a client-side siteinfo
 * lookup, which only works when the wiki is publicly readable.
 *
 * In 404 mode, the directory is shown only when CANASTA_ENABLE_WIKI_DIRECTORY is "true".
 * In directory mode, the directory is always shown (the caller already checked the env var).
 */

$directoryOnly = !empty( $directoryOnly );
$showDirectory = $directoryOnly || ( getenv( 'CANASTA_ENABLE_WIKI_DIRECTORY' ) === 'true' );
$scheme = parse_url( getenv( 'MW_SITE_SERVER' ) ?: 'https://localhost', PHP_URL_SCHEME ) ?: 'https';
$requestedPath = isset( $urlComponents['path'] ) ? htmlspecialchars( $urlComponents['path'], ENT_QUOTES, 'UTF-8' ) : '/';
$pageTitle = $directoryOnly ? 'Wiki Directory' : 'Page Not Found';

$publicAssetsRoot = getenv( 'MW_VOLUME' ) ? rtrim( getenv( 'MW_VOLUME' ), '/' ) . '/public_assets' : '';

// Extensions accepted for a conventional logo, in the order they win when a
// wiki has more than one.
$logoExtensions = [ 'svg', 'png', 'webp', 'jpg', 'jpeg', 'gif' ];

/**
 * Find a wiki's conventional logo file name, or null when it has none.
 * The wiki ID is used as a path segment, so anything that could escape the
 * public_assets root is rejected rather than sanitized.
 */
$findWikiLogo = static function ( $wikiId ) use ( $publicAssetsRoot, $logoExtensions ) {
	if ( $publicAssetsRoot === '' || $wikiId === '' || preg_match( '#[/\\\\]|^\.#', $wikiId ) ) {
		return null;
	}
	$entries = @scandir( $publicAssetsRoot . '/' . $wikiId );
	if ( $entries === false ) {
		return null;
	}
	// The name is matched case-insensitively; scandir sorts, so when a wiki
	// holds both "Logo.png" and "logo.png" the first in sorted order wins.
	$byExtension = [];
	foreach ( $entries as $entry ) {
		if ( preg_match( '/^logo\.([A-Za-z]+)$/i', $entry, $m ) ) {
			$extension = strtolower( $m[1] );
			if ( !isset( $byExtension[$extension] ) ) {
				$byExtension[$extension] = $entry;
			}
		}
	}
	foreach ( $logoExtensions as $extension ) {
		if ( isset( $byExtension[$extension] ) ) {
			return $byExtension[$extension];
		}
	}
	return null;
};

?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?php echo $pageTitle; ?></title>
<style>
*,*::before,*::after{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:#f5f5f5;color:#333}
.container{max-width:960px;margin:0 auto;padding:40px 20px}
.error-box{background:#fff;border:1px solid #ddd;border-radius:8px;padding:40px;text-align:center;margin-bottom:40px}
.error-box h1{font-size:48px;margin:0 0 8px;color:#c00}
.error-box p{font-size:18px;margin:0;color:#555}
.error-box code{background:#f0f0f0;padding:2px 8px;border-radius:4px;font-size:16px}
.directory h2{font-size:22px;margin:0 0 20px;color:#333}
.wiki-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}
.wiki-card{background:#fff;border:1px solid #ddd;border-radius:8px;overflow:hidden;transition:box-shadow .15s}
.wiki-card:hover{box-shadow:0 2px 8px rgba(0,0,0,.12)}
.wiki-card a{display:block;text-decoration:none;color:inherit;padding:20px;text-align:center}
.wiki-card .logo{width:80px;height:80px;margin:0 auto 12px;display:flex;align-items:center;justify-content:center}
.wiki-card .logo img{max-width:80px;max-height:80px}
.wiki-card .logo img[data-api]{display:none}
.wiki-card .name{font-size:16px;font-weight:600;color:#0645ad}
</style>
</head>
<body>
<div class="container">
<?php if ( !$directoryOnly ): ?>
  <div class="error-box">
    <h1>404</h1>
    <p>Page not found: <code><?php echo $requestedPath; ?></code></p>
  </div>
<?php endif; ?>
<?php if ( $showDirectory && isset( $wikiConfigurations['wikis'] ) && is_array( $wikiConfigurations['wikis'] ) ): ?>
  <div class="directory">
    <h2>Available wikis</h2>
    <div class="wiki-grid">
<?php foreach ( $wikiConfigurations['wikis'] as $wiki ):
	$rawWikiId = (string)( $wiki['id'] ?? '' );
	$rawWikiUrl = $scheme . '://' . (string)( $wiki['url'] ?? '' );
	$wikiName = htmlspecialchars( $wiki['name'] ?? $wiki['id'] ?? 'Wiki', ENT_QUOTES, 'UTF-8' );
	$wikiUrl = htmlspecialchars( $rawWikiUrl, ENT_QUOTES, 'UTF-8' );
	$wikiId = htmlspecialchars( $rawWikiId, ENT_QUOTES, 'UTF-8' );
	$logoFile = $findWikiLogo( $rawWikiId );
	$logoAttr = $logoFile !== null
		? 'src="' . htmlspecialchars( $rawWikiUrl . '/public_assets/' . rawurlencode( $logoFile ), ENT_QUOTES, 'UTF-8' ) . '"'
		: 'data-api="' . $wikiUrl . '/w/api.php"';
?>
      <div class="wiki-card">
        <a href="<?php echo $wikiUrl; ?>">
          <div class="logo"><img alt="" data-wiki-id="<?php echo $wikiId; ?>" <?php echo $logoAttr; ?>></div>
          <div class="name"><?php echo $wikiName; ?></div>
        </a>
      </div>
<?php endforeach; ?>
    </div>
  </div>
<script>
// A server-resolved logo file can still fail to load — a wiki added to
// wikis.yaml since the last restart has no public_assets rewrite yet.
// Hide those rather than leaving a broken-image glyph in the card.
document.querySelectorAll('.wiki-card img[src]').forEach(function(img) {
  var hide = function() {
    img.style.display = 'none';
  };
  if (img.complete && img.naturalWidth === 0) {
    hide();
    return;
  }
  img.addEventListener('error', hide);
});
document.querySelectorAll('.wiki-card img[data-api]').forEach(function(img) {
  var url = img.getAttribute('data-api') +
    '?action=query&meta=siteinfo&siprop=general&format=json&origin=*';
  fetch(url).then(function(r) {
    if (!r.ok) throw 0;
    return r.json();
  }).then(function(d) {
    var logo = d && d.query && d.query.general && d.query.general.logo;
    if (!logo) return;
    var test = new Image();
    test.onload = function() {
      img.src = logo;
      img.style.display = 'block';
    };
    test.src = logo;
  }).catch(function() {});
});
</script>
<?php endif; ?>
</div>
</body>
</html>
