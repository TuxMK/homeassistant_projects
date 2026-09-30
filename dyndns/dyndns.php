<?php
/**
 * DynDNS2-compatible update endpoint for DNS zones hosted at mittwald (API v2).
 *
 * UniFi "Dynamic DNS" -> custom service:
 *   Hostname : sub.example.com                (record to update, comma-separated list allowed)
 *   Username : example.com                    (domain the hostname must belong to)
 *   Password : <mittwald API token>
 *   Server   : dyndns.familie-loebbe.de/nic/update?hostname=%h&myip=%i
 *
 * Upload as index.php together with the .htaccess from this folder; it routes /nic/update
 * to this script and passes the Basic auth header through to PHP-FPM.
 *
 * Responses follow the dyndns2 protocol: good, nochg, badauth, notfqdn, nohost, dnserr, 911.
 */

declare(strict_types=1);

const API_BASE    = 'https://api.mittwald.de/v2';
const TTL_SECONDS = 60;     // used when the record set has no TTL yet (mittwald minimum: 60)
const CREATE_ZONE = true;   // create the subdomain zone if it does not exist yet

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

function respond(string $body, int $status = 200): never
{
    http_response_code($status);
    echo $body, "\n";
    exit;
}

function logMsg(string $msg): void
{
    error_log('[dyndns] ' . $msg);
}

/**
 * Returns [user, password] from Basic auth, falling back to query parameters.
 */
function credentials(): array
{
    $user = $_SERVER['PHP_AUTH_USER'] ?? null;
    $pass = $_SERVER['PHP_AUTH_PW'] ?? null;

    // PHP-FPM/CGI does not populate PHP_AUTH_* on its own
    if ($user === null) {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        if (stripos($header, 'Basic ') === 0) {
            $decoded = base64_decode(substr($header, 6), true);
            if ($decoded !== false && str_contains($decoded, ':')) {
                [$user, $pass] = explode(':', $decoded, 2);
            }
        }
    }

    $user ??= $_GET['username'] ?? $_GET['user'] ?? '';
    $pass ??= $_GET['password'] ?? $_GET['pass'] ?? '';

    return [strtolower(trim((string)$user, " \t.")), trim((string)$pass)];
}

/**
 * Calls the mittwald API and returns [status, decoded body].
 */
function api(string $method, string $path, string $token, ?array $body = null): array
{
    $ch = curl_init(API_BASE . $path);
    $headers = ['Authorization: Bearer ' . $token, 'Accept: application/json'];
    if ($body !== null) {
        $headers[] = 'Content-Type: application/json';
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_SLASHES));
    }
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 20,
    ]);
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        logMsg("$method $path failed: $error");
        respond('911', 500);
    }
    return [$status, json_decode($raw, true)];
}

function isValidHostname(string $host): bool
{
    return strlen($host) <= 253
        && preg_match('/^(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$/', $host) === 1;
}

// --- Input --------------------------------------------------------------

[$domain, $token] = credentials();
if ($domain === '' || $token === '') {
    header('WWW-Authenticate: Basic realm="dyndns"');
    respond('badauth', 401);
}
if (!isValidHostname($domain)) {
    respond('notfqdn');
}

$hostnames = array_filter(array_map(
    fn($h) => strtolower(trim($h, " \t.")),
    explode(',', (string)($_GET['hostname'] ?? ''))
));
if ($hostnames === []) {
    respond('notfqdn');
}
foreach ($hostnames as $host) {
    if (!isValidHostname($host)) {
        respond('notfqdn');
    }
    // Only real subdomains of the domain given as username may be changed
    if (!str_ends_with($host, '.' . $domain)) {
        logMsg("rejected $host: not a subdomain of $domain");
        respond('nohost');
    }
}

// myip may contain an IPv4 and/or IPv6 address, comma-separated; fall back to the client address
$ipv4 = null;
$ipv6 = null;
$rawIps = trim((string)($_GET['myip'] ?? ''));
foreach (explode(',', $rawIps !== '' ? $rawIps : ($_SERVER['REMOTE_ADDR'] ?? '')) as $ip) {
    $ip = trim($ip);
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        $ipv4 = $ip;
    } elseif (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
        $ipv6 = $ip;
    }
}
if ($ipv4 === null && $ipv6 === null) {
    logMsg("no valid IP in '$rawIps'");
    respond('911', 400);
}

// --- Locate the project that holds the domain ------------------------------

[$status, $projects] = api('GET', '/projects', $token);
if ($status === 401 || $status === 403) {
    respond('badauth', 401);
}
if ($status !== 200 || !is_array($projects)) {
    logMsg("listing projects failed: HTTP $status");
    respond('911', 502);
}

$projectId = null;
$zones = [];
foreach ($projects as $project) {
    [$status, $projectZones] = api('GET', '/projects/' . rawurlencode($project['id']) . '/dns-zones', $token);
    if ($status !== 200 || !is_array($projectZones)) {
        continue;
    }
    foreach ($projectZones as $zone) {
        if (strtolower($zone['domain']) === $domain) {
            $projectId = $project['id'];
            $zones = $projectZones;
            break 2;
        }
    }
}
if ($projectId === null) {
    logMsg("domain $domain not found in any project");
    respond('nohost');
}

// --- Update each hostname ------------------------------------------------

$results = [];
foreach ($hostnames as $host) {
    $zone = null;
    foreach ($zones as $candidate) {
        if (strtolower($candidate['domain']) === $host) {
            $zone = $candidate;
            break;
        }
    }

    if ($zone === null) {
        if (!CREATE_ZONE) {
            $results[] = 'nohost';
            continue;
        }
        [$status, $created] = api('POST', '/projects/' . rawurlencode($projectId) . '/dns-zones', $token, ['name' => $host]);
        if ($status !== 201 || empty($created['id'])) {
            logMsg("creating zone $host failed: HTTP $status " . json_encode($created));
            $results[] = 'dnserr';
            continue;
        }
        [$status, $zone] = api('GET', '/dns-zones/' . rawurlencode($created['id']), $token);
        if ($status !== 200 || !is_array($zone)) {
            logMsg("fetching new zone $host failed: HTTP $status");
            $results[] = 'dnserr';
            continue;
        }
        logMsg("created zone $host");
    }

    // Keep the address family that was not sent (e.g. existing AAAA when only IPv4 is updated)
    $current = $zone['recordSet']['combinedARecords'] ?? [];
    $currentA = $current['a'] ?? [];
    $currentAaaa = $current['aaaa'] ?? [];
    $newA = $ipv4 !== null ? [$ipv4] : $currentA;
    $newAaaa = $ipv6 !== null ? [$ipv6] : $currentAaaa;
    $shownIp = implode(',', array_filter([$ipv4, $ipv6]));

    // Never take over records managed by an ingress (hosted website), that would break the site
    if (isset($current['managedBy'])) {
        logMsg("rejected $host: A records are managed by an ingress");
        $results[] = 'nohost';
        continue;
    }
    if ($newA === $currentA && $newAaaa === $currentAaaa) {
        $results[] = 'nochg ' . $shownIp;
        continue;
    }

    $settings = $current['settings'] ?? [];
    if (empty($settings['ttl'])) {
        $settings['ttl'] = ['seconds' => TTL_SECONDS];
    }

    [$status, $error] = api('PUT', '/dns-zones/' . rawurlencode($zone['id']) . '/record-sets/a', $token, [
        'a'        => $newA,
        'aaaa'     => $newAaaa,
        'settings' => $settings,
    ]);
    if ($status !== 204) {
        logMsg("updating $host failed: HTTP $status " . json_encode($error));
        $results[] = 'dnserr';
        continue;
    }

    logMsg("updated $host -> $shownIp");
    $results[] = 'good ' . $shownIp;
}

respond(implode("\n", $results));
