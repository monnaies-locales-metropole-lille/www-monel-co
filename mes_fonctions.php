<?php
/**
 * Cyclos API Client for Monel
 *
 * Provides functions to fetch user data from Cyclos REST API with caching.
 */

if (!defined('_ECRIRE_INC_VERSION')) {
  return;
}

/**
 * Build Cyclos image URL
 *
 * @param array|string $image Image data (object with 'id') or direct ID
 * @param int $width Image width
 * @param int $height Image height
 * @return string|null Image URL or null if no image
 */
function cyclos_image_url($image, $width = 120, $height = 120) {
  if (empty($image)) {
    return null;
  }

  // Handle both array (from JSON decode) and string
  $image_id = is_array($image) && isset($image['id']) ? $image['id'] : $image;

  if (empty($image_id)) {
    return null;
  }

  $api_url = defined('_CYCLOS_API_URL') ? _CYCLOS_API_URL : '';
  return $api_url . '/images/content/' . $image_id . '?width=' . $width . '&height=' . $height;
}

/**
 * Fetch users from Cyclos API
 *
 * @param int $page Page number (0-indexed)
 * @param int|null $pageSize Number of results per page (null = use config default)
 * @param string|null $keywords Search keywords
 * @return array ['users' => array, 'total' => int, 'has_next' => bool, 'error' => string|null]
 */
function cyclos_fetch_users($page = 0, $pageSize = null, $keywords = null) {
  // Load config
  $api_url = defined('_CYCLOS_API_URL') ? _CYCLOS_API_URL : '';
  $access_token = defined('_CYCLOS_ACCESS_TOKEN') ? _CYCLOS_ACCESS_TOKEN : '';
  $cache_duration = defined('_CYCLOS_CACHE_DURATION') ? _CYCLOS_CACHE_DURATION : 900;

  if (empty($api_url) || empty($access_token)) {
    return [
      'users' => [],
      'total' => 0,
      'has_next' => false,
      'error' => 'Cyclos API not configured'
    ];
  }

  if ($pageSize === null) {
    $pageSize = defined('_CYCLOS_PAGE_SIZE') ? _CYCLOS_PAGE_SIZE : 40;
  }

  // Build cache key
  $cache_key = 'cyclos_users_p' . $page . '_s' . $pageSize;
  if (!empty($keywords)) {
    $cache_key .= '_k' . md5($keywords);
  }
  $cache_key .= '.json';

  // Check cache
  include_spip('inc/flock');
  $cache_dir = sous_repertoire(_DIR_CACHE, 'cyclos');
  $cache_file = $cache_dir . $cache_key;

  if (file_exists($cache_file)) {
    $cache_age = time() - filemtime($cache_file);
    if ($cache_age < $cache_duration) {
      // Cache is fresh
      $cached_data = file_get_contents($cache_file);
      $result = json_decode($cached_data, true);
      if ($result) {
        return $result;
      }
    }
  }

  // Build API request URL
  $endpoint = $api_url . '/users';
  $params = [
    'page' => $page,
    'pageSize' => $pageSize,
    'fields' => 'id,display,name,username,image,email,customValues'
  ];

  if (!empty($keywords)) {
    $params['keywords'] = $keywords;
  }

  $url = $endpoint . '?' . http_build_query($params);

  // Make API request
  include_spip('inc/distant');
  $options = [
    'headers' => [
      'Access-Client-Token' => $access_token,
      'Accept' => 'application/json'
    ]
  ];

  $response = recuperer_url($url, $options);

  if (!$response) {
    // API failed, try to use stale cache
    if (file_exists($cache_file)) {
      $cached_data = file_get_contents($cache_file);
      $result = json_decode($cached_data, true);
      if ($result) {
        $result['error'] = 'Using stale cache (API unavailable)';
        return $result;
      }
    }

    return [
      'users' => [],
      'total' => 0,
      'has_next' => false,
      'error' => 'Failed to fetch users from Cyclos API'
    ];
  }

  // Parse response body and headers
  // recuperer_url returns the body directly
  $body = $response;

  // Try to parse JSON
  $data = json_decode($body, true);

  if (!$data) {
    return [
      'users' => [],
      'total' => 0,
      'has_next' => false,
      'error' => 'Invalid JSON response from Cyclos API'
    ];
  }

  // Extract headers from the response
  // Note: We need to get headers separately using recuperer_page
  $page_data = recuperer_page($url, false, false, 0, $options);
  $headers = isset($page_data['headers']) ? $page_data['headers'] : '';

  // Parse X-Total-Count and X-Has-Next-Page headers
  $total = 0;
  $has_next = false;

  if (preg_match('/X-Total-Count:\s*(\d+)/i', $headers, $matches)) {
    $total = intval($matches[1]);
  }

  if (preg_match('/X-Has-Next-Page:\s*(true|false)/i', $headers, $matches)) {
    $has_next = ($matches[1] === 'true');
  }

  // Pre-process users to flatten image field
  $users = [];
  foreach ($data as $user) {
    // Flatten image to image_url
    if (isset($user['image']) && is_array($user['image']) && isset($user['image']['id'])) {
      $user['image_url'] = cyclos_image_url($user['image']);
    } else {
      $user['image_url'] = null;
    }

    $users[] = $user;
  }

  // Build result
  $result = [
    'users' => $users,
    'total' => $total,
    'has_next' => $has_next,
    'error' => null
  ];

  // Cache the result
  ecrire_fichier($cache_file, json_encode($result));

  return $result;
}

/**
 * SPIP filter to fetch Cyclos annuaire data
 *
 * This filter stores the fetched data in $GLOBALS for template access
 * and returns a dummy value for the DATA loop
 *
 * @param mixed $dummy Dummy input (ignored)
 * @param int $page Page number (0-indexed)
 * @param string|null $keywords Search keywords
 * @return string JSON-encoded array containing the data
 */
function filtre_cyclos_annuaire_data_dist($dummy = '', $page = 0, $keywords = null) {
  $result = cyclos_fetch_users($page, null, $keywords);

  // Store in globals for template access
  $GLOBALS['cyclos_data'] = $result;

  // Return JSON for DATA loop
  return json_encode($result);
}
