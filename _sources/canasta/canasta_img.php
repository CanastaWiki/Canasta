<?php
/**
 * The web entry point for serving non-public images to logged-in users in the Canasta project.
 *
 * This file is specifically configured for the Canasta project. In Canasta, images for each wiki
 * are stored in their specific directories, located at /mediawiki/images/$wikiID.
 * 
 * This script also includes functionality for 'canasta_img', which helps in redirecting users
 * to their corresponding image locations. If the 'wikis.yaml' file does not exist, 
 * the script will function as originally designed.
 *
 * For general setup, see https://www.mediawiki.org/wiki/Manual:Image_Authorization
 *
 * Configuration:
 * - Set $wgUploadDirectory to point to the non-public directory where images are stored. 
 *   For Canasta, this would be /mediawiki/images/$wikiID.
 * - Set $wgUploadPath to point to this file.
 *
 * Optional Parameters:
 * - Set $wgImgAuthDetails = true to display denial reason messages instead of just a 403 error.
 *   This can be useful for debugging but is generally not recommended for production use.
 * 
 * Server Requirements:
 * Your server needs to support REQUEST_URI or PATH_INFO; some CGI-based configurations don't.
 *
 * License:
 * This program is free software under the GNU General Public License.
 *
 * @file
 * @ingroup entrypoint
 * @author Chenhao Liu
 */

define( 'MW_NO_OUTPUT_COMPRESSION', 1 );
define( 'MW_ENTRY_POINT', 'canasta_img' );
require __DIR__ . '/includes/WebStart.php';

wfImageAuthMain();

$mediawiki = new MediaWiki();
$mediawiki->doPostOutputShutdown();

function wfImageAuthMain() {
	global $wgImgAuthUrlPathMap, $wgScriptPath, $wgImgAuthPath, $wikiID;

	$services = \MediaWiki\MediaWikiServices::getInstance();
	$permissionManager = $services->getPermissionManager();

	$request = RequestContext::getMain()->getRequest();
	$publicWiki = in_array( 'read', $services->getGroupPermissionsLookup()->getGroupPermissions( [ '*' ] ), true );

	// Find the path assuming the request URL is relative to the local public zone URL
	$baseUrl = $services->getRepoGroup()->getLocalRepo()->getZoneUrl( 'public' );
	if ( $baseUrl[0] === '/' ) {
		$basePath = $baseUrl;
	} else {
		$basePath = parse_url( $baseUrl, PHP_URL_PATH );
	}
	$path = WebRequest::getRequestPathSuffix( $basePath );

	if ( $path === false ) {
		// Try instead assuming canasta_img.php is the base path
		$basePath = $wgImgAuthPath ?: "$wgScriptPath/canasta_img.php";
		$path = WebRequest::getRequestPathSuffix( $basePath );
	}

	if ( $path === false ) {
		wfForbidden( 'img-auth-accessdenied', 'img-auth-notindir' );
		return;
	}

	if ( $path === '' || $path[0] !== '/' ) {
		// Make sure $path has a leading /
		$path = "/" . $path;
	}

	if ( isset( $wikiID ) && !empty( $wikiID ) ) {
		// Replace "/images" | "/canasta_img.php" with "/images/$wikiID" | "/canasta_img.php/$wikiID" in the path.
		$path = str_replace_last( "/images", "/images/$wikiID", $path );
		$path = str_replace_last( "/canasta_img.php", "/canasta_img.php/$wikiID", $path );
	} else {
		error_log( 'Warning: wikiID is not set or empty' );
	}

	$user = RequestContext::getMain()->getUser();

	// Various extensions may have their own backends that need access.
	// Check if there is a special backend and storage base path for this file.
	foreach ( $wgImgAuthUrlPathMap as $prefix => $storageDir ) {
		$prefix = rtrim( $prefix, '/' ) . '/'; // implicit trailing slash
		if ( strpos( $path, $prefix ) === 0 ) {
			$be = $services->getFileBackendGroup()->backendFromPath( $storageDir );
			$filename = $storageDir . substr( $path, strlen( $prefix ) ); // strip prefix
			// Check basic user authorization
			$isAllowedUser = $permissionManager->userHasRight( $user, 'read' );
			if ( !$isAllowedUser ) {
				wfForbidden( 'img-auth-accessdenied', 'img-auth-noread', $path );
				return;
			}
			if ( $be->fileExists( [ 'src' => $filename ] ) ) {
				wfDebugLog( 'canasta_img', "Streaming `" . $filename . "`." );
				$be->streamFile( [
					'src' => $filename,
					'headers' => [ 'Cache-Control: private', 'Vary: Cookie' ]
				] );
			} else {
				wfForbidden( 'img-auth-accessdenied', 'img-auth-nofile', $path );
			}
			return;
		}
	}

	// Get the local file repository
	$repo = $services->getRepoGroup()->getRepo( 'local' );
	$zone = strstr( ltrim( $path, '/' ), '/', true );

	// Get the full file storage path and extract the source file name.
	// (e.g. 120px-Foo.png => Foo.png or page2-120px-Foo.png => Foo.png).
	// This only applies to thumbnails/transcoded, and each of them should
	// be under a folder that has the source file name.
	if ( $zone === 'thumb' || $zone === 'transcoded' ) {
		$name = wfBaseName( dirname( $path ) );
		$filename = $repo->getZonePath( $zone ) . substr( $path, strlen( "/" . $zone ) );
		// Check to see if the file exists
		if ( !$repo->fileExists( $filename ) ) {
			wfForbidden( 'img-auth-accessdenied', 'img-auth-nofile', $filename );
			return;
		}
	} else {
		$name = wfBaseName( $path ); // file is a source file
		$filename = $repo->getZonePath( 'public' ) . $path;
		// Check to see if the file exists and is not deleted
		$bits = explode( '!', $name, 2 );
		if ( substr( $path, 0, 9 ) === '/archive/' && count( $bits ) == 2 ) {
			$file = $repo->newFromArchiveName( $bits[1], $name );
		} else {
			$file = $repo->newFile( $name );
		}
		if ( !$file->exists() || $file->isDeleted( File::DELETED_FILE ) ) {
			wfForbidden( 'img-auth-accessdenied', 'img-auth-nofile', $filename );
			return;
		}
	}

	$headers = []; // extra HTTP headers to send

	$title = Title::makeTitleSafe( NS_FILE, $name );

	if ( !$publicWiki ) {
		// For private wikis, run extra auth checks and set cache control headers
		$headers['Cache-Control'] = 'private';
		$headers['Vary'] = 'Cookie';

		if ( !$title instanceof Title ) { // files have valid titles
			wfForbidden( 'img-auth-accessdenied', 'img-auth-badtitle', $name );
			return;
		}

		// Run hook for extension authorization plugins
		/** @var array $result */
		$result = null;
		if ( !Hooks::runner()->onImgAuthBeforeStream( $title, $path, $name, $result ) ) {
			wfForbidden( $result[0], $result[1], array_slice( $result, 2 ) );
			return;
		}

		// Check user authorization for this title
		// Checks Whitelist too

		if ( !$permissionManager->userCan( 'read', $user, $title ) ) {
			wfForbidden( 'img-auth-accessdenied', 'img-auth-noread', $name );
			return;
		}
	}

	if ( isset( $_SERVER['HTTP_RANGE'] ) ) {
		$headers['Range'] = $_SERVER['HTTP_RANGE'];
	}
	if ( isset( $_SERVER['HTTP_IF_MODIFIED_SINCE'] ) ) {
		$headers['If-Modified-Since'] = $_SERVER['HTTP_IF_MODIFIED_SINCE'];
	}

	if ( $request->getCheck( 'download' ) ) {
		$headers['Content-Disposition'] = 'attachment';
	}

	// Allow modification of headers before streaming a file
	Hooks::runner()->onImgAuthModifyHeaders( $title->getTitleValue(), $headers );

	// Stream the requested file
	list( $headers, $options ) = HTTPFileStreamer::preprocessHeaders( $headers );
	wfDebugLog( 'canasta_img', "Streaming `" . $filename . "`." );
	$repo->streamFileWithStatus( $filename, $headers, $options );
}

/**
 * Issue a standard HTTP 403 Forbidden header ($msg1-a message index, not a message) and an
 * error message ($msg2, also a message index), (both required) then end the script
 * subsequent arguments to $msg2 will be passed as parameters only for replacing in $msg2
 * @param string $msg1
 * @param string $msg2
 * @param mixed ...$args To pass as params to wfMessage() with $msg2. Either variadic, or a single
 *   array argument.
 */
function wfForbidden( $msg1, $msg2, ...$args ) {
	global $wgImgAuthDetails;

	$args = ( isset( $args[0] ) && is_array( $args[0] ) ) ? $args[0] : $args;

	$msgHdr = wfMessage( $msg1 )->text();
	$detailMsgKey = $wgImgAuthDetails ? $msg2 : 'badaccess-group0';
	$detailMsg = wfMessage( $detailMsgKey, $args )->text();

	wfDebugLog( 'canasta_img',
		"wfForbidden Hdr: " . wfMessage( $msg1 )->inLanguage( 'en' )->text() . " Msg: " .
			wfMessage( $msg2, $args )->inLanguage( 'en' )->text()
	);

	HttpStatus::header( 403 );
	header( 'Cache-Control: no-cache' );
	header( 'Content-Type: text/html; charset=utf-8' );
	$templateParser = new TemplateParser();
	echo $templateParser->processTemplate( 'ImageAuthForbidden', [
		'msgHdr' => $msgHdr,
		'detailMsg' => $detailMsg,
	] );
}

function str_replace_last( $search, $replace, $subject ) {
	if ( ( $pos = strrpos( $subject, $search ) ) !== false ) {
		$subject = substr_replace( $subject, $replace, $pos, strlen( $search ) );
	}
	return $subject;
}
