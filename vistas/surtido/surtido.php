<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Base app dinámica y ruta relativa para validación
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Surtido y Compras';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Surtido y Compras</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Surtido</a>
            </div>
        </div>
    </div>
    <style>
        .table-responsive { overflow-x: auto; }
        .table th, .table td { vertical-align: middle; font-size: 0.92rem; }
        .section-header { margin-bottom: 1rem; }
        .controls-inline > * { margin-right: 0.5rem; }
    </style>
</div>
<!-- Page Header End -->

<div class="blog">
    <div class="container">
        <div class="section-header text-center">
            <p>Filtros</p>
            <div class="d-flex justify-content-center mb-3 controls-inline">
                <input type="date" id="filtroDesde" class="form-control" style="max-width: 200px;">
                <input type="date" id="filtroHasta" class="form-control" style="max-width: 200px;">
                <button id="btnAplicar" class="btn custom-btn">Aplicar filtros</button>
            </div>
            <small>Por defecto se usa el periodo semanal actual.</small>
        </div>

        <!-- Entradas de insumos -->
        <div class="mb-4">
            <div class="d-flex justify-content-between align-items-center mb-2">
                <h4>Entradas de Insumos</h4>
                <input type="text" id="buscarEntradas" class="form-control" placeholder="Buscar" style="max-width: 260px;">
            </div>
            <div class="table-responsive">
                <table class="table table-striped table-sm">
                    <thead class="thead-light">
                        <tr>
                            <th>Fecha</th>
                            <th>Insumo</th>
                            <th>Unidad</th>
                            <th class="text-right">Cantidad</th>
                            <th class="text-right">Costo total</th>
                            <th class="text-right">Valor unitario</th>
                            <th>Proveedor</th>
                            <th>Usuario</th>
                            <th>Descripción</th>
                            <th>Referencia</th>
                            <th>Folio fiscal</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyEntradas"></tbody>
                </table>
            </div>
            <ul id="paginadorEntradas" class="pagination justify-content-center"></ul>
        </div>

        <!-- Lead time por insumo -->
        <div class="mb-4">
            <div class="d-flex justify-content-between align-items-center mb-2">
                <h4>Lead time de reabasto por insumo</h4>
                <div class="d-flex align-items-center">
                    <div class="form-check mr-3">
                        <input class="form-check-input" type="checkbox" id="ltIncluirCeros">
                        <label class="form-check-label" for="ltIncluirCeros">Incluir ceros</label>
                    </div>
                    <input type="text" id="buscarLead" class="form-control" placeholder="Buscar" style="max-width: 220px;">
                </div>
            </div>
            <div class="table-responsive">
                <table class="table table-striped table-sm">
                    <thead class="thead-light">
                        <tr>
                            <th>Insumo</th>
                            <th class="text-right">Pares</th>
                            <th class="text-right">Prom. días</th>
                            <th class="text-right">Mín</th>
                            <th class="text-right">Máx</th>
                            <th>Última entrada</th>
                            <th>Próxima estimada</th>
                            <th class="text-right">Días restantes</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyLead"></tbody>
                </table>
            </div>
            <ul id="paginadorLead" class="pagination justify-content-center"></ul>
        </div>

        <!-- Resumen por insumo (todos) -->
        <div class="mb-4">
            <div class="d-flex justify-content-between align-items-center mb-2">
                <h4>Resumen por insumo (todos)</h4>
                <div class="d-flex align-items-center">
                    <div class="form-check mr-3">
                        <input class="form-check-input" type="checkbox" id="rpIncluirCeros">
                        <label class="form-check-label" for="rpIncluirCeros">Incluir ceros</label>
                    </div>
                    <input type="text" id="buscarResumenInsumo" class="form-control" placeholder="Buscar" style="max-width: 220px;">
                </div>
            </div>
            <div class="table-responsive">
                <table class="table table-striped table-sm">
                    <thead class="thead-light">
                        <tr>
                            <th>Insumo</th>
                            <th class="text-right">Compras</th>
                            <th class="text-right">Monto total</th>
                            <th class="text-right">Costo medio</th>
                            <th class="text-right">Costo prom. unit.</th>
                            <th class="text-right">Cantidad total</th>
                            <th>Primera compra</th>
                            <th>Última compra</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyResumenInsumo"></tbody>
                </table>
            </div>
            <ul id="paginadorResumenInsumo" class="pagination justify-content-center"></ul>
        </div>

        <!-- Resumen compras global -->
        <div class="mb-4">
            <h4>Resumen de compras (global)</h4>
            <div class="table-responsive">
                <table class="table table-striped table-sm">
                    <thead class="thead-light">
                        <tr>
                            <th>Compras</th>
                            <th class="text-right">Monto total</th>
                            <th class="text-right">Costo medio</th>
                            <th class="text-right">Costo prom. unit.</th>
                            <th class="text-right">Cantidad total</th>
                            <th>Primera compra</th>
                            <th>Última compra</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyResumenGlobal"></tbody>
                </table>
            </div>
        </div>

        <!-- Resumen compras por insumo (uno) -->
        <div class="mb-4">
            <div class="d-flex justify-content-between align-items-center mb-2">
                <h4>Resumen de compras por insumo (uno)</h4>
                <div class="d-flex align-items-center">
                    <select id="selectInsumo" class="form-control" style="min-width: 260px;"></select>
                    <button id="btnConsultarInsumo" class="btn custom-btn ml-2">Consultar</button>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table table-striped table-sm">
                    <thead class="thead-light">
                        <tr>
                            <th>Insumo</th>
                            <th class="text-right">Compras</th>
                            <th class="text-right">Monto total</th>
                            <th class="text-right">Costo medio</th>
                            <th class="text-right">Costo prom. unit.</th>
                        </tr>
                    </thead>
                    <tbody id="tbodyResumenInsumoUno"></tbody>
                </table>
            </div>
        </div>

    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="surtido.js"></script>
</body>
</html>

<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
