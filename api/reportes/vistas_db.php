<?php
/**
 * Endpoint genérico para consultar vistas de base de datos.
 * Para agregar una nueva vista, inclúyela en el arreglo $whitelist y
 * agrega su etiqueta legible en el mapa viewLabels de vistas_db.js.
 */
header('Content-Type: application/json');

$whitelist = [
    'vista_productos_mas_vendidos',
    'vista_resumen_cortes',
    'vista_resumen_pagos',
    'vista_ventas_diarias',
    'vista_ventas_por_mesero',
    'vw_consumo_insumos',
    'vw_corte_resumen',
    'vw_ventas_detalladas',
    'logs_accion',
    'log_asignaciones_mesas',
    'log_mesas',
    'movimientos_insumos',
    'fondo',
    'insumos',
    'tickets',
    'ventas',
    'qrs_insumo'
];

try {
    // Conexión
    $config = __DIR__ . '/../../config/db.php';
    if (file_exists($config)) {
        require $config; // provee $host, $user, $pass, $db
    }
    $host = $host ?? getenv('DB_HOST') ?? 'localhost';
    $db   = $db   ?? getenv('DB_NAME') ?? 'restaurante';
    $user = $user ?? getenv('DB_USER') ?? 'root';
    $pass = $pass ?? getenv('DB_PASS') ?? '';
    $dsn = "mysql:host={$host};dbname={$db};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $action = $_GET['action'] ?? '';

    if ($action === 'list_sources') {
        // Construir listas de vistas y tablas existentes, filtradas por whitelist
        $views = [];
        $tables = [];
        // Obtener todas las vistas/tables del esquema actual
        $stmtV = $pdo->query("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = DATABASE()");
        $allViews = array_column($stmtV->fetchAll(), 'TABLE_NAME');
        $stmtT = $pdo->query("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE='BASE TABLE'");
        $allTables = array_column($stmtT->fetchAll(), 'TABLE_NAME');
        foreach ($whitelist as $name) {
            if (in_array($name, $allViews, true)) $views[] = $name;
            elseif (in_array($name, $allTables, true)) $tables[] = $name;
        }
        echo json_encode(['views' => $views, 'tables' => $tables], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if ($action === 'fetch') {
        $source = $_GET['source'] ?? '';
        if (!in_array($source, $whitelist, true)) {
            http_response_code(400);
            echo json_encode(['error' => 'Fuente no permitida']);
            exit;
        }
        $page = max(1, (int)($_GET['page'] ?? 1));
        $pageSize = (int)($_GET['pageSize'] ?? 15);
        $pageSize = $pageSize > 0 ? $pageSize : 15;
        $search = trim($_GET['q'] ?? '');
        $sortBy = $_GET['sortBy'] ?? '';
        $sortDir = strtolower($_GET['sortDir'] ?? 'asc');
        $sortDir = $sortDir === 'desc' ? 'DESC' : 'ASC';

        $stmt = $pdo->prepare("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t ORDER BY ORDINAL_POSITION");
        $stmt->execute([':t' => $source]);
        $columnsInfo = $stmt->fetchAll();
        if (!$columnsInfo) {
            http_response_code(400);
            echo json_encode(['error' => 'Fuente no encontrada']);
            exit;
        }
        $columns = array_column($columnsInfo, 'COLUMN_NAME');
        if (!in_array($sortBy, $columns, true)) $sortBy = '';

        $allowedTypes = ['char','varchar','text','tinytext','mediumtext','longtext','int','bigint','smallint','mediumint','decimal','float','double','date','datetime','timestamp','time','year'];
        $where = '';
        $params = [];
        if ($search !== '') {
            $parts = [];
            foreach ($columnsInfo as $idx => $col) {
                if (in_array(strtolower($col['DATA_TYPE']), $allowedTypes, true)) {
                    $ph = ":s{$idx}";
                    $parts[] = "`{$col['COLUMN_NAME']}` LIKE {$ph}";
                    $params[$ph] = "%{$search}%";
                }
            }
            if ($parts) $where = ' WHERE ' . implode(' OR ', $parts);
        }
        $offset = ($page - 1) * $pageSize;
        $countSql = "SELECT COUNT(*) FROM `{$source}`{$where}";
        $countStmt = $pdo->prepare($countSql);
        foreach ($params as $ph => $val) $countStmt->bindValue($ph, $val);
        $countStmt->execute();
        $total = (int)$countStmt->fetchColumn();

        $dataSql = "SELECT * FROM `{$source}`{$where}";
        if ($sortBy) $dataSql .= " ORDER BY `{$sortBy}` {$sortDir}";
        $dataSql .= " LIMIT :limit OFFSET :offset";
        $dataStmt = $pdo->prepare($dataSql);
        foreach ($params as $ph => $val) $dataStmt->bindValue($ph, $val);
        $dataStmt->bindValue(':limit', $pageSize, PDO::PARAM_INT);
        $dataStmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $dataStmt->execute();
        $rows = $dataStmt->fetchAll();
        echo json_encode([
            'columns' => $columns,
            'rows' => $rows,
            'total' => $total,
            'page' => $page,
            'pageSize' => $pageSize,
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    if ($action === 'export_csv') {
        $source = $_GET['source'] ?? '';
        if (!in_array($source, $whitelist, true)) {
            http_response_code(400);
            echo json_encode(['error' => 'Fuente no permitida']);
            exit;
        }
        $search = trim($_GET['q'] ?? '');
        $sortBy = $_GET['sortBy'] ?? '';
        $sortDir = strtolower($_GET['sortDir'] ?? 'asc');
        $sortDir = $sortDir === 'desc' ? 'DESC' : 'ASC';

        $stmt = $pdo->prepare("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t ORDER BY ORDINAL_POSITION");
        $stmt->execute([':t' => $source]);
        $columnsInfo = $stmt->fetchAll();
        if (!$columnsInfo) {
            http_response_code(400);
            echo json_encode(['error' => 'Fuente no encontrada']);
            exit;
        }
        $columns = array_column($columnsInfo, 'COLUMN_NAME');
        if (!in_array($sortBy, $columns, true)) $sortBy = '';

        $allowedTypes = ['char','varchar','text','tinytext','mediumtext','longtext','int','bigint','smallint','mediumint','decimal','float','double','date','datetime','timestamp','time','year'];
        $where = '';
        $params = [];
        if ($search !== '') {
            $parts = [];
            foreach ($columnsInfo as $idx => $col) {
                if (in_array(strtolower($col['DATA_TYPE']), $allowedTypes, true)) {
                    $ph = ":s{$idx}";
                    $parts[] = "`{$col['COLUMN_NAME']}` LIKE {$ph}";
                    $params[$ph] = "%{$search}%";
                }
            }
            if ($parts) $where = ' WHERE ' . implode(' OR ', $parts);
        }

        $sql = "SELECT * FROM `{$source}`{$where}";
        if ($sortBy) $sql .= " ORDER BY `{$sortBy}` {$sortDir}";
        $st = $pdo->prepare($sql);
        foreach ($params as $ph => $val) $st->bindValue($ph, $val);
        $st->execute();
        $rows = $st->fetchAll();

        // CSV headers
        header('Content-Type: text/csv; charset=utf-8');
        $fname = $source . '-' . date('Ymd_His') . '.csv';
        header('Content-Disposition: attachment; filename="' . $fname . '"');

        $out = fopen('php://output', 'w');
        // BOM for Excel UTF-8
        fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));
        fputcsv($out, $columns);
        foreach ($rows as $row) {
            $line = [];
            foreach ($columns as $c) {
                $v = isset($row[$c]) ? $row[$c] : '';
                // Normalize newlines to spaces
                if (is_string($v)) { $v = preg_replace('/\r?\n/', ' ', $v); }
                $line[] = $v;
            }
            fputcsv($out, $line);
        }
        fclose($out);
        exit;
    }

    // Compatibilidad con vistas_db.js (parámetros: view, per_page, search, sort_by, sort_dir)
    $view = $_GET['view'] ?? '';
    if (!in_array($view, $whitelist, true)) {
        http_response_code(400);
        echo json_encode(['error' => 'Vista no permitida']);
        exit;
    }
    $page = max(1, (int)($_GET['page'] ?? 1));
    $perPage = (int)($_GET['per_page'] ?? 15);
    $perPage = in_array($perPage, [15,25,50], true) ? $perPage : 15;
    $search = trim($_GET['search'] ?? '');
    $sortBy = $_GET['sort_by'] ?? '';
    $sortDir = strtolower($_GET['sort_dir'] ?? 'asc');
    $sortDir = $sortDir === 'desc' ? 'DESC' : 'ASC';

    $stmt = $pdo->prepare("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :view ORDER BY ORDINAL_POSITION");
    $stmt->execute([':view' => $view]);    
    $columnsInfo = $stmt->fetchAll();
    if (!$columnsInfo) {
        http_response_code(400);
        echo json_encode(['error' => 'Vista no encontrada']);
        exit;
    }
    $columns = array_column($columnsInfo, 'COLUMN_NAME');
    if (!in_array($sortBy, $columns, true)) {
        $sortBy = '';
    }

    $allowedTypes = ['char','varchar','text','tinytext','mediumtext','longtext','int','bigint','smallint','mediumint','decimal','float','double','date','datetime','timestamp','time','year'];
    $where = '';
    $params = [];
    if ($search !== '') {
        $parts = [];
        foreach ($columnsInfo as $idx => $col) {
            if (in_array(strtolower($col['DATA_TYPE']), $allowedTypes, true)) {
                $ph = ":s{$idx}";
                $parts[] = "`{$col['COLUMN_NAME']}` LIKE {$ph}";
                $params[$ph] = "%{$search}%";
            }
        }
        if ($parts) {
            $where = ' WHERE ' . implode(' OR ', $parts);
        }
    }

    $offset = ($page - 1) * $perPage;

    $countSql = "SELECT COUNT(*) FROM `{$view}`{$where}";
    $countStmt = $pdo->prepare($countSql);
    foreach ($params as $ph => $val) {
        $countStmt->bindValue($ph, $val);
    }
    $countStmt->execute();
    $total = (int)$countStmt->fetchColumn();

    $dataSql = "SELECT * FROM `{$view}`{$where}";
    if ($sortBy) {
        $dataSql .= " ORDER BY `{$sortBy}` {$sortDir}";
    }
    $dataSql .= " LIMIT :limit OFFSET :offset";

    $dataStmt = $pdo->prepare($dataSql);
    foreach ($params as $ph => $val) {
        $dataStmt->bindValue($ph, $val);
    }
    $dataStmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
    $dataStmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    $dataStmt->execute();
    $rows = $dataStmt->fetchAll();

    echo json_encode([
        'columns' => $columns,
        'rows' => $rows,
        'total' => $total,
        'page' => $page,
        'per_page' => $perPage,
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
