<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$path_actual = str_replace('/CDI', '', $_SERVER['PHP_SELF']);
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Cortes Almacén';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Cortes de Almacén</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Cortes</a>
            </div>
        </div>
    </div>
</div>

<div class="container mt-4">
    <div class="mb-3">
        <button class="btn custom-btn me-2" id="btnAbrirCorte">Abrir corte</button>
        <button class="btn custom-btn me-2" id="btnCerrarCorte">Cerrar corte</button>
        <button class="btn custom-btn" id="btnExportarExcel">Exportar a Excel</button>
    </div>
    <div id="formObservaciones" class="mb-3" style="display:none;">
        <textarea id="observaciones" class="form-control mb-2" placeholder="Observaciones"></textarea>
        <button class="btn custom-btn" id="guardarCierre">Guardar cierre</button>
    </div>
    <div class="mb-3">
        <label for="buscarFecha">Fecha:</label>
        <input type="date" id="buscarFecha" class="form-control-sm">
        <button class="btn custom-btn-sm" id="btnBuscar">Buscar</button>
    </div>
    <div class="mb-3">
        <select id="listaCortes" class="form-select form-select-sm">
            <option value="">Seleccione corte...</option>
        </select>
    </div>
    <div class="row mb-2">
        <div class="col-md-6 mb-2">
            <input type="text" id="filtroInsumo" class="form-control form-control-sm" placeholder="Buscar insumo">
        </div>
        <div class="col-md-3">
            <select id="registrosPagina" class="form-select form-select-sm">
                <option value="15">15</option>
                <option value="25">25</option>
                <option value="50">50</option>
            </select>
        </div>
    </div>
    <div class="table-responsive">
        <table id="tablaResumen" class="styled-table">
            <thead>
                <tr>
                    <th>Insumo</th>
                    <th>Inicial</th>
                    <th>Entradas</th>
                    <th>Salidas</th>
                    <th>Mermas</th>
                    <th>Final</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
        <div class="d-flex justify-content-between mt-2">
            <button class="btn custom-btn-sm" id="prevPagina">&lt;</button>
            <button class="btn custom-btn-sm" id="nextPagina">&gt;</button>
        </div>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="cortes.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
