<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$path_actual = str_replace('/CDI', '', $_SERVER['PHP_SELF']);
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Entradas de Proveedor';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Entradas de Insumos</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Entradas de proveedor</a>
            </div>
        </div>
    </div>
</div>

<div class="container mt-5">
    <h2 class="text-white">Registrar entrada</h2>
    <form id="formEntrada" class="bg-dark p-4 rounded">
        <div class="form-group mb-2">
            <label class="text-white" for="proveedor_id">Proveedor:</label>
            <select id="proveedor_id" class="form-control"></select>
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="insumo_id">Insumo:</label>
            <select id="insumo_id" class="form-control"></select>
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="cantidad">Cantidad:</label>
            <input type="number" step="0.01" id="cantidad" class="form-control">
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="unidad">Unidad:</label>
            <input type="text" id="unidad" class="form-control">
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="costo_total">Costo total:</label>
            <input type="number" step="0.01" id="costo_total" class="form-control">
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="valor_unitario">Valor unitario:</label>
            <input type="number" step="0.01" id="valor_unitario" class="form-control" readonly>
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="descripcion">Descripción:</label>
            <textarea id="descripcion" class="form-control"></textarea>
        </div>
        <div class="form-group mb-2">
            <label class="text-white" for="referencia_doc">Referencia doc:</label>
            <input type="text" id="referencia_doc" class="form-control">
        </div>
        <div class="form-group mb-3">
            <label class="text-white" for="folio_fiscal">Folio fiscal:</label>
            <input type="text" id="folio_fiscal" class="form-control">
        </div>
        <button type="submit" class="btn custom-btn">Guardar</button>
    </form>
</div>

<div class="container mt-5">
    <h2 class="text-white">Historial de Entradas</h2>
    <div class="table-responsive">
        <table id="tablaHistorial" class="styled-table">
            <thead>
                <tr>
                    <th>Fecha</th>
                    <th>Proveedor</th>
                    <th>Insumo</th>
                    <th>Cantidad</th>
                    <th>Unidad</th>
                    <th>Costo total</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="entradas_proveedor.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
