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
 * Fetch the labels of the `code_naf_v4` selection field from Cyclos
 *
 * The user list only returns the selected option id, so the labels
 * ("9499Z - Autres organisations ...") are resolved from the search metadata.
 *
 * @return array [option id => label]
 */
function cyclos_naf_labels() {
  $api_url = defined('_CYCLOS_API_URL') ? _CYCLOS_API_URL : '';
  $access_token = defined('_CYCLOS_ACCESS_TOKEN') ? _CYCLOS_ACCESS_TOKEN : '';
  $group = defined('_CYCLOS_USER_GROUP') ? _CYCLOS_USER_GROUP : '';

  if (empty($api_url) || empty($access_token)) {
    return [];
  }

  // Option list rarely changes: cache it for a day
  include_spip('inc/flock');
  $cache_file = sous_repertoire(_DIR_CACHE, 'cyclos') . 'naf_labels.json';
  if (file_exists($cache_file) && time() - filemtime($cache_file) < 86400) {
    $labels = json_decode(file_get_contents($cache_file), true);
    if (is_array($labels)) {
      return $labels;
    }
  }

  $url = $api_url . '/users/data-for-search';
  if (!empty($group)) {
    $url .= '?' . http_build_query(['groups' => $group]);
  }

  include_spip('inc/distant');
  $response = recuperer_url($url, [
    'headers' => [
      'Access-Client-Token' => $access_token,
      'Accept' => 'application/json'
    ]
  ]);

  $data = is_array($response) ? json_decode($response['page'], true) : null;
  $labels = [];
  foreach ((is_array($data) && isset($data['customFields'])) ? $data['customFields'] : [] as $field) {
    if (($field['internalName'] ?? '') === 'code_naf_v4') {
      foreach ($field['possibleValues'] ?? [] as $value) {
        $labels[$value['id']] = $value['value'];
      }
    }
  }

  if ($labels) {
    ecrire_fichier($cache_file, json_encode($labels));
  } elseif (file_exists($cache_file)) {
    // API failed: fall back to stale cache
    $labels = json_decode(file_get_contents($cache_file), true) ?: [];
  }

  return $labels;
}

/**
 * Translate a NAF code into a readable activity sector (NAF section level)
 *
 * @param string $naf NAF code or label, e.g. "9499Z - Autres organisations..."
 * @return string|null Sector label, or null if the code is not recognized
 */
function naf_secteur($naf) {
  if (!preg_match('/^\s*(\d{2})/', (string) $naf, $matches)) {
    return null;
  }
  $division = intval($matches[1]);

  // [last division of the section => sector label]
  $sections = [
    3  => 'Agriculture, sylviculture et pêche',
    9  => 'Industries extractives',
    33 => 'Industrie et fabrication',
    35 => 'Production d\'énergie',
    39 => 'Eau, gestion des déchets et dépollution',
    43 => 'Construction et BTP',
    47 => 'Commerce',
    53 => 'Transports et logistique',
    56 => 'Hébergement et restauration',
    63 => 'Information, communication et numérique',
    66 => 'Banque et assurance',
    68 => 'Immobilier',
    75 => 'Conseil, études et services aux entreprises',
    82 => 'Services administratifs et de soutien',
    84 => 'Administration publique',
    85 => 'Enseignement et formation',
    88 => 'Santé et action sociale',
    93 => 'Culture, sports et loisirs',
    96 => 'Associations et services à la personne',
    98 => 'Particuliers employeurs',
    99 => 'Organisations extraterritoriales',
  ];

  foreach ($sections as $last => $label) {
    if ($division <= $last) {
      return $label;
    }
  }
  return null;
}

/**
 * Fetch all annuaire users and group them by activity sector
 *
 * @param string|null $keywords Search keywords
 * @return array ['groups' => [['secteur' => string, 'users' => array]], 'total' => int, 'error' => string|null]
 */
function cyclos_fetch_annuaire($keywords = null) {
  $users = [];
  $error = null;

  // Grouping needs the whole directory: walk all pages (capped as a safety net)
  for ($page = 0; $page < 20; $page++) {
    $result = cyclos_fetch_users($page, 100, $keywords);
    $users = array_merge($users, $result['users']);
    $error = $error ?: $result['error'];
    if (!$result['has_next']) {
      break;
    }
  }

  $labels = $users ? cyclos_naf_labels() : [];
  $autres = 'Autres adhérents';
  $groups = [];

  foreach ($users as $user) {
    $values = is_array($user['customValues'] ?? null) ? $user['customValues'] : [];
    $naf = $values['code_naf_v4'] ?? '';
    $naf = $labels[$naf] ?? $naf;
    $secteur = naf_secteur($naf) ?: $autres;
    $groups[$secteur][] = $user;
  }

  // Sort sectors alphabetically, members without a sector last
  uksort($groups, function ($a, $b) use ($autres) {
    if ($a === $autres || $b === $autres) {
      return ($a === $autres) - ($b === $autres);
    }
    return strnatcasecmp($a, $b);
  });

  $result = [];
  foreach ($groups as $secteur => $members) {
    $result[] = ['secteur' => $secteur, 'users' => $members];
  }

  return [
    'groups' => $result,
    'total' => count($users),
    'error' => $error
  ];
}

/**
 * SPIP filter to fetch Cyclos annuaire data grouped by activity sector
 *
 * Returns the result array so the template can capture it with #SET and read
 * it via #GET{...}|table_valeur{...} (groups / total / error).
 *
 * @param mixed $dummy Dummy input (ignored)
 * @param string|null $keywords Search keywords
 * @return array ['groups' => array, 'total' => int, 'error' => string|null]
 */
function filtre_cyclos_annuaire_data_dist($dummy = '', $keywords = null) {
  // Return the result array directly so the template can capture it with #SET
  return cyclos_fetch_annuaire($keywords);
}
