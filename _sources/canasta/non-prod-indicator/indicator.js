( function () {
	var HIDE_MS = 20000;
	var hideTimer;

	function init() {
		if ( document.querySelector( '.wikiteq-nonprod-label' ) ) {
			return;
		}

		var frame = document.createElement( 'div' );
		frame.className = 'wikiteq-nonprod-frame';
		frame.setAttribute( 'aria-hidden', 'true' );

		var button = document.createElement( 'button' );
		button.type = 'button';
		button.className = 'wikiteq-nonprod-label';
		button.textContent = 'NOT PRODUCTION';
		button.title = 'Hide this overlay for 20 seconds';
		button.addEventListener( 'click', function () {
			document.body.classList.add( 'wikiteq-nonprod-hidden' );
			clearTimeout( hideTimer );
			hideTimer = setTimeout( function () {
				document.body.classList.remove( 'wikiteq-nonprod-hidden' );
			}, HIDE_MS );
		} );

		document.body.appendChild( frame );
		document.body.appendChild( button );
	}

	if ( document.body ) {
		init();
	} else {
		document.addEventListener( 'DOMContentLoaded', init );
	}
}() );
