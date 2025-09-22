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
$title = 'Entradas • Pagos';
ob_start();
?>

<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Entradas de Insumos - Pagos</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Entradas - Pagos</a>
            </div>
        </div>
    </div>
    </div>

<div class="container mt-4">
    <div class="bg-dark p-3 rounded">
        <div class="row g-2 align-items-end">
            <div class="col-sm-6 col-md-3">
                <label class="text-white" for="filtroCredito">Tipo de pago</label>
                <select id="filtroCredito" class="form-control">
                    <option value="">Todos</option>
                    <option value="0">Efectivo</option>
                    <option value="1">Crédito</option>
                </select>
            </div>
            <div class="col-sm-6 col-md-3">
                <label class="text-white" for="filtroPagado">Pagado</label>
                <select id="filtroPagado" class="form-control">
                    <option value="">Todos</option>
                    <option value="0">No pagado</option>
                    <option value="1">Pagado</option>
                </select>
            </div>
            <div class="col-sm-6 col-md-4">
                <label class="text-white" for="busqueda">Buscar</label>
                <input type="text" id="busqueda" class="form-control" placeholder="Proveedor, producto, referencia, folio...">
            </div>
            <div class="col-sm-6 col-md-2 text-end">
                <button class="btn custom-btn w-100" id="btnBuscar">Filtrar</button>
            </div>
        </div>
    </div>

    <div class="mt-3 d-flex justify-content-between align-items-center">
        <h4 class="text-white m-0">Listado de entradas</h4>
        <div>
            <button class="btn btn-secondary" id="seleccionarTodo">Seleccionar todo</button>
            <button class="btn btn-secondary" id="deseleccionarTodo">Deseleccionar</button>
            <button class="btn custom-btn" id="btnMarcarPagado">Marcar como pagado</button>
        </div>
    </div>

    <div class="table-responsive mt-2">
        <table id="tablaEntradasPagos" class="styled-table">
            <thead>
                <tr>
                    <th><input type="checkbox" id="checkAll"></th>
                    <th>ID</th>
                    <th>Fecha</th>
                    <th>Proveedor</th>
                    <th>Producto</th>
                    <th>Cantidad</th>
                    <th>Unidad</th>
                    <th>Costo total</th>
                    <th>Tipo pago</th>
                    <th>Pagado</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
</div>

<!-- Modal global de mensajes -->
<div class="modal fade" id="appMsgModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">Mensaje</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body"></div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
 </div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="entradas_pagos.js" defer></script>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

