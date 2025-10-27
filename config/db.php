<?php
// Configuración de BD para CDI con compatibilidad mysqli ($conn) y PDOs opcionales

if (!function_exists('env')) {
    function env(string $key, $default = null) {
        $val = getenv($key);
        return ($val !== false && $val !== null) ? $val : $default;
    }
}

// --- mysqli principal (BD actual CDI) ---
if (!function_exists('get_db')) {
    function get_db(): mysqli {
        static $conn = null;
        if ($conn instanceof mysqli) return $conn;
        $host = env('CDI_DB_HOST', 'localhost');
        $user = env('CDI_DB_USER', 'root');
        $pass = env('CDI_DB_PASS', '');
        $db   = env('CDI_DB_NAME', 'restaurante_cdis');
        $conn = @new mysqli($host, $user, $pass, $db);
        if ($conn->connect_errno) {
            http_response_code(500);
            die('Error de conexión: ' . $conn->connect_error);
        }
        $conn->set_charset('utf8mb4');
        return $conn;
    }
}

if (!isset($conn) || !($conn instanceof mysqli)) {
    $conn = get_db();
}

// --- PDOs opcionales (para insertar en otras BDs si se requiere) ---
if (class_exists('PDO')) {
    if (!function_exists('pdo_connect')) {
        function pdo_connect(string $dsn, string $user, string $pass): PDO {
            $pdo = new PDO($dsn, $user, $pass, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
            $pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_general_ci");
            return $pdo;
        }
    }

    // DSNs tipo rest/config/db.php pero con prefijos CDI_
    $cdi1_dsn  = env('CDI_DB1_DSN', 'mysql:host=localhost;dbname=restaurante;charset=utf8mb4');
    $cdi1_user = env('CDI_DB1_USER', env('CDI_DB_USER', 'root'));
    $cdi1_pass = env('CDI_DB1_PASS', env('CDI_DB_PASS', ''));

    $cdi2_dsn  = env('CDI_DB2_DSN', 'mysql:host=localhost;dbname=restaurante;charset=utf8mb4');
    $cdi2_user = env('CDI_DB2_USER', env('CDI_DB_USER', 'root'));
    $cdi2_pass = env('CDI_DB2_PASS', env('CDI_DB_PASS', ''));

    $cdi3_dsn  = env('CDI_DB3_DSN', 'mysql:host=localhost;dbname=restaurante_cdi;charset=utf8mb4');
    $cdi3_user = env('CDI_DB3_USER', env('CDI_DB_USER', 'root'));
    $cdi3_pass = env('CDI_DB3_PASS', env('CDI_DB_PASS', ''));

    try { $pdoCdi1 = pdo_connect($cdi1_dsn, $cdi1_user, $cdi1_pass); } catch (Throwable $e) { $pdoCdi1 = null; }
    try { $pdoCdi2 = pdo_connect($cdi2_dsn, $cdi2_user, $cdi2_pass); } catch (Throwable $e) { $pdoCdi2 = null; }
    try { $pdoCdi3 = pdo_connect($cdi3_dsn, $cdi3_user, $cdi3_pass); } catch (Throwable $e) { $pdoCdi3 = null; }

    // Opciones publicables para selector en vistas
    $CDI_DB_OPTIONS = [
        'db1' => [ 'label' => env('CDI_DB1_NAME', 'BD 1'), 'pdo' => $pdoCdi1 ],
        'db2' => [ 'label' => env('CDI_DB2_NAME', 'BD 2'), 'pdo' => $pdoCdi2 ],
        'db3' => [ 'label' => env('CDI_DB3_NAME', 'BD 3'), 'pdo' => $pdoCdi3 ],
    ];

    if (!function_exists('cdi_pdo_by_key')) {
        function cdi_pdo_by_key(string $key): ?PDO {
            global $CDI_DB_OPTIONS;
            if (!isset($CDI_DB_OPTIONS[$key])) return null;
            $opt = $CDI_DB_OPTIONS[$key];
            return ($opt['pdo'] ?? null) instanceof PDO ? $opt['pdo'] : null;
        }
    }
}
?>
