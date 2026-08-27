<?php

/**
 * Runtime options for www.monel.co — baked into the image.
 *
 * Contains NO secrets: every credential is read from the environment so that the
 * image is safe to store in a registry and identical across environments.
 *
 * Derived from the mes_options.php recovered from the prod webroot, not from a
 * development checkout — the two differ (see _BAZAAR_VIDEO_ID below).
 */

if (!defined('_ECRIRE_INC_VERSION')) {
	return;
}

/**
 * Fail loudly rather than silently running misconfigured.
 */
function monel_env(string $name, ?string $default = null): string {
	$value = getenv($name);
	if ($value === false || $value === '') {
		if ($default !== null) {
			return $default;
		}
		http_response_code(500);
		error_log("FATAL: required environment variable $name is not set");
		exit(1);
	}
	return $value;
}

// ---------------------------------------------------------------------------
// Writable paths
// ---------------------------------------------------------------------------

// tmp/ lives outside the webroot. Compiled skeletons are the directory the
// 2026-08-21 payload executed from; keeping it off the document root means it
// cannot be requested over HTTP under any misconfiguration.
define('_DIR_TMP', '/var/spip/tmp/');

// connect.php and cles.php are mounted read-only as secrets, also outside the webroot.
define('_DIR_CONNECT', '/var/spip/secrets/');
define('_DIR_ETC', '/var/spip/secrets/');

// ---------------------------------------------------------------------------
// File permissions
// ---------------------------------------------------------------------------

// SPIP applies this to mkdir() directly and to files as (_SPIP_CHMOD & 0666).
// 0750 therefore yields 0750 directories and 0640 files.
//
// The previous value was 0777, which is how /var/www/mlml.fr ended up with
// world-writable files throughout its plugin tree (incident report §5.8).
// Never raise this.
if (!defined('_SPIP_CHMOD')) {
	define('_SPIP_CHMOD', 0750);
}

// ---------------------------------------------------------------------------
// Hardening
// ---------------------------------------------------------------------------

// Plugin installation and core upgrade from the back office are prevented by the
// filesystem, not by a flag: plugins/ and ecrire/ are root-owned and mode 0555, and
// spip_loader.php is deleted at build time. SVP simply finds nothing writable.
// The image is the only way to change code.

// Do not advertise the exact SPIP version to scanners.
define('_HEADER_COMPOSED_BY', false);

// ---------------------------------------------------------------------------
// Application settings
// ---------------------------------------------------------------------------

// Spam protection for the "nous rejoindre" form (formulaires/rejoindre.php).
// This was live on prod; without it the form loses nospam coverage entirely.
$GLOBALS['formulaires_no_spam'][] = 'rejoindre';

// Bazaar video ID (SPIP article ID of the "comment ça marche" video).
// 50 is the production article. Development checkouts use 26 — do not copy that
// value across; the article ids are per-database.
define('_BAZAAR_VIDEO_ID', (int) monel_env('MONEL_BAZAAR_VIDEO_ID', '50'));

// ---------------------------------------------------------------------------
// Cyclos API — not in production
// ---------------------------------------------------------------------------
// The integration lives on the `cyclos-api` branch and has never been deployed;
// the prod mes_options.php recovered from the compromised webroot contains no
// Cyclos configuration at all. These constants are therefore defined only when
// the environment supplies them, so the production image runs without them and
// the branch works by setting the variables rather than by editing this file.
//
// The token is a secret: inject it, never commit it.
if (getenv('CYCLOS_API_URL') && getenv('CYCLOS_ACCESS_TOKEN')) {
	define('_CYCLOS_API_URL', monel_env('CYCLOS_API_URL'));
	define('_CYCLOS_ACCESS_TOKEN', monel_env('CYCLOS_ACCESS_TOKEN'));
	define('_CYCLOS_CACHE_DURATION', (int) monel_env('CYCLOS_CACHE_DURATION', '900'));
	define('_CYCLOS_PAGE_SIZE', (int) monel_env('CYCLOS_PAGE_SIZE', '40'));
	define('_CYCLOS_USER_GROUP', monel_env('CYCLOS_USER_GROUP', 'members'));
}
