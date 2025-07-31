<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$path_actual = str_replace('/CDI', '', $_SERVER['PHP_SELF']);
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

<div class="container mt-5 mb-5 custom-modal">
    <h1 class="titulo-seccion">Reportes de Cortes</h1>

    <div class="filtros-container">
        <label for="filtroUsuario">Usuario:</label>
        <select id="filtroUsuario" class="form-control-sm"></select>

        <label for="filtroInicio">Inicio:</label>
        <input type="date" id="filtroInicio" class="form-control-sm">

        <label for="filtroFin">Fin:</label>
        <input type="date" id="filtroFin" class="form-control-sm">

        <button id="aplicarFiltros" class="btn custom-btn-sm">Buscar</button>
        <button id="btnImprimir" class="btn custom-btn-sm">Imprimir</button>
    </div>

    <div class="acciones-corte mt-3">
        <button id="btnResumen" class="btn custom-btn">Resumen de corte actual</button>
    </div>

    <div id="modal" class="custom-modal" style="display:none;"></div>

</div>

<div class="container mt-5 mb-5">
    <h2 class="section-header">Historial de Cortes</h2>
    <table id="tablaCortes">
        <thead>
            <tr>
                <th>ID</th>
                <th>Usuario</th>
                <th>Fecha inicio</th>
                <th>Fecha cierre</th>
                <th>Total</th>
                <th>Efectivo</th>
                <th>Tarjeta</th>
                <th>Cheque</th>
                <th>Fondo</th>
                <th>Observaciones</th>
                <th>Detalle</th>
            </tr>
        </thead>
        <tbody>

        </tbody>
    </table>

</div>
<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="reportes.js"></script>
</body>

</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
