<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Reportes';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Modulo de Reportes</h2>
            </div>
            <div class="col-12">
                <a href="">Inicio</a>
                <a href="">Reporteria del sistema</a>
            </div>
        </div>
    </div>
    </div>
<!-- Page Header End -->

<div class="container mt-5 mb-5">
    <h2 class="section-header">Consulta de Vistas y Tablas</h2>

    <div class="filtros-container">
        <label for="selectFuente">Fuente:</label>
        <select id="selectFuente" class="form-control-sm"></select>

        <label for="buscarFuente">Buscar:</label>
        <input type="text" id="buscarFuente" class="form-control-sm" placeholder="Buscar...">

        <label for="tamPagina">Filas por página:</label>
        <select id="tamPagina" class="form-control-sm">
            <option value="15">15</option>
            <option value="25">25</option>
            <option value="50">50</option>
        </select>
        <button id="btnExportCSV" class="btn custom-btn-sm" style="margin-left:8px;">Exportar CSV</button>
    </div>

    <div id="reportesLoader" style="display:none;">Cargando...</div>

    <table id="tablaReportes" class="styled-table mt-3">
        <thead></thead>
        <tbody></tbody>
    </table>

    <div id="paginacionReportes" class="mt-3">
        <button id="prevReportes" class="btn custom-btn-sm">Anterior</button>
        <span id="infoReportes" class="mx-2"></span>
        <button id="nextReportes" class="btn custom-btn-sm">Siguiente</button>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="reportes.js"></script>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

