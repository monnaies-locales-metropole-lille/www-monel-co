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

  // Public member group (internal name) to restrict the directory to
  $group = defined('_CYCLOS_USER_GROUP') ? _CYCLOS_USER_GROUP : '';

  // Build cache key
  $cache_key = 'cyclos_users_p' . $page . '_s' . $pageSize;
  if (!empty($group)) {
    $cache_key .= '_g' . $group;
  }
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

  if (!empty($group)) {
    $params['groups'] = $group;
  }

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

  // recuperer_url() returns ['status' => int, 'headers' => string, 'page' => string, ...]
  $http_status = is_array($response) ? intval($response['status']) : 0;
  $body    = is_array($response) ? $response['page'] : '';
  $headers = is_array($response) ? $response['headers'] : '';
  if (is_array($headers)) {
    $headers = implode("\n", array_map(function ($k, $v) { return "$k: $v"; },
      array_keys($headers), array_values($headers)));
  }

  if ($http_status < 200 || $http_status >= 300 || $body === '') {
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
      'error' => 'Failed to fetch users from Cyclos API (HTTP ' . $http_status . ')'
    ];
  }

  // Try to parse JSON body
  $data = json_decode($body, true);

  if (!is_array($data)) {
    return [
      'users' => [],
      'total' => 0,
      'has_next' => false,
      'error' => 'Invalid JSON response from Cyclos API'
    ];
  }

  // Parse pagination from response headers (Cyclos: X-Total-Count / X-Has-Next-Page)
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
 * Returns the result array so the template can capture it with #SET and read
 * it via #GET{...}|table_valeur{...} (users / total / has_next / error).
 *
 * @param mixed $dummy Dummy input (ignored)
 * @param int $page Page number (0-indexed)
 * @param string|null $keywords Search keywords
 * @return array ['users' => array, 'total' => int, 'has_next' => bool, 'error' => string|null]
 */
function filtre_cyclos_annuaire_data_dist($dummy = '', $page = 0, $keywords = null) {
  // Return the result array directly so the template can capture it with #SET
  return cyclos_fetch_users($page, null, $keywords);
}
