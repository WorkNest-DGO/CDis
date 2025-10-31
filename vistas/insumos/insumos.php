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
$title = 'Insumos';
ob_start();
?>
<div id="corte-info" data-corte-id="<?= isset($__corte_id_abierto) ? (int)$__corte_id_abierto : 0; ?>" hidden></div>
<?php
// Validar corte abierto para mostrar la seccin de Registro de entradas
$__corte_id_abierto = 0;
try {
    if (isset($conn) && $conn) {
        $stmtC = $conn->prepare("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1");
        if ($stmtC) {
            if ($stmtC->execute()) {
                $resC = $stmtC->get_result();
                if ($resC && ($rowC = $resC->fetch_assoc())) {
                    $__corte_id_abierto = (int)$rowC['id'];
                }
            }
            $stmtC->close();
        }
    }
} catch (Throwable $e) {
    $__corte_id_abierto = 0;
}
$__mostrar_registro_entrada = ($__corte_id_abierto > 0);
?>
<style>
    .is-invalid { outline: 2px solid #e74c3c; }
</style>

<!-- Page Header Start -->
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Ingredientes</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Inventario de ingredientes</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->



<!-- Blog Start -->
<div class="blog">
    <div class="container">
        <div class="section-header text-center">
            <p>Insumos</p>
            <h2>Recuerda validar los datos antes de guardar altas</h2>
            <div class="d-flex justify-content-center mb-3">
                <a class="btn custom-btn me-2" type="button" id="btnNuevoInsumo">Nuevo insumo</a>
            </div>
            <div class="d-flex justify-content-center mb-3">
                <input type="text" id="buscarInsumo" class="form-control text-end" placeholder="Buscar">
            </div>
                <div class="row">
        <div class="col-12">
            <ul id="paginador" class="pagination justify-content-center"></ul>
        </div>
    </div>
        </div>
        <div class="row" id="catalogoInsumos"></div>

        <div class="modal fade" id="modalInsumo" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog" role="document">
                <div style="color:black" class="modal-content">
                    <form id="formInsumo">
                        <div class="modal-header">
                            <h5  style="color:black" class="modal-title">Insumo</h5>
                            <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                        </div>
                        <div class="modal-body">
                            <input type="hidden" id="insumoId">
                            <div class="form-group">
                                <label for="nombre">Nombre:</label>
                                <input type="text" id="nombre" class="form-control">
                            </div>
                            <div class="form-group">
                                <label for="unidad">Unidad:</label>
                                <input type="text" id="unidad" class="form-control">
                            </div>
                            <div class="form-group">
                                <label for="existencia">Existencia:</label>
                                <input type="number" step="0.01" id="existencia" class="form-control" value="0" readonly>
                            </div>
                            <div class="form-group">
                                <label for="minimo_stock">Mínimo en stock:</label>
                                <input type="number" step="0.01" min="0" id="minimo_stock" class="form-control" placeholder="0.00" required>
                            </div>
                            <div class="form-group">
                                <label for="tipo_control">Tipo:</label>
                                <select id="tipo_control" class="form-control">
                                    <option value="por_receta">por_receta</option>
                                    <option value="unidad_completa">unidad_completa</option>
                                    <option value="uso_general">uso_general</option>
                                    <option value="no_controlado">no_controlado</option>
                                    <option value="desempaquetado">desempaquetado</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label for="reque_id">Área/Requerimiento:</label>
                                <select id="reque_id" class="form-control" required>
                                    <option value="" disabled selected>--Selecciona--</option>
                                    <?php
                                    try {
                                        if (!isset($conn)) { require_once __DIR__ . '/../../config/db.php'; }
                                        $rsRt = $conn->query('SELECT id, nombre FROM reque_tipos WHERE activo = 1 ORDER BY nombre');
                                        if ($rsRt) {
                                            while ($rt = $rsRt->fetch_assoc()) {
                                                $rid = (int)$rt['id']; $rnom = htmlspecialchars($rt['nombre'] ?? '', ENT_QUOTES, 'UTF-8');
                                                echo '<option value="' . $rid . '">' . $rnom . '</option>';
                                            }
                                        }
                                    } catch (Throwable $e) {}
                                    ?>
                                </select>
                            </div>
                            <div class="form-group">
                                <label for="imagen">Imagen:</label>
                                <input type="file" id="imagen" class="form-control">
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button class="btn custom-btn me-2" type="submit">Guardar</button>
                            <button class="btn custom-btn me-2" type="button" id="cancelarInsumo" data-dismiss="modal">Cancelar</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

    </div>

</div>
</div>
<!-- Blog End -->

<!-- insumo -->
<div id="sec-reg-entrada" class="container mt-5" style="<?= $__mostrar_registro_entrada ? '' : 'display:none'; ?>">
    <h2 class="text-white">Registrar entrada de productos</h2>
    <form  id="form-entrada" class="bg-dark p-4 rounded" name="form-entrada">
        <div class="form-group">
            <label for="proveedor" class="text-white">Proveedor:</label>
            <div class="selector-proveedor position-relative">
                <input type="text" class="form-control buscador-proveedor" placeholder="Buscar proveedor...">
                <select id="proveedor" name="proveedor_id" class="form-control d-none"></select>
                <ul class="list-group lista-proveedores position-absolute w-100" style="z-index: 1000;"></ul>
            </div>
            <button type="button" id="btnNuevoProveedor" class="btn custom-btn mt-2">Nuevo proveedor</button>
        </div>

        <div class="form-group">
            <label class="text-white d-block">Tipo de pago:</label>
            <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="credito" id="pagoEfectivo" value="efectivo" checked>
                <label class="form-check-label text-white" for="pagoEfectivo">Efectivo</label>
            </div>
            <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="credito" id="pagoCredito" value="credito">
                <label class="form-check-label text-white" for="pagoCredito">Crédito</label>
            </div>
            <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="credito" id="pagoTransferencia" value="transferencia">
                <label class="form-check-label text-white" for="pagoTransferencia">Transferencia</label>
            </div>
        </div>

        <div class="row g-3 mb-3">
            <div class="col-sm-6">
                <label for="notaFisica" class="text-white">Nota física</label>
                <input type="text" id="notaFisica" name="referencia_doc" class="form-control" placeholder="Ej. Ticket/Nota del proveedor">
                <label for="folioFiscal" class="text-white">Folio fiscal</label>
                <input type="text" id="folioFiscal" name="folio_fiscal" class="form-control" placeholder="UUID de la factura (si aplica)">
            </div>

        </div>

        
            <table id="tablaProductos" class="styled-table">
                <thead>
                    <tr>
                        <th>Producto</th>
                        <th>Tipo de control</th>
                        <th>Cantidad</th>
                        <th>Unidad</th>
                        <th>Costo total</th>
                    </tr>
                </thead>
                <tbody>
                    <tr class="fila-producto">
                        <td>
                            <div class="selector-insumo position-relative">
                                <input type="text" class="form-control buscador-insumo" placeholder="Buscar insumo...">
                                <select class="form-control insumo_id d-none" name="insumo_id"></select>
                                <ul class="list-group lista-insumos position-absolute w-100" style="z-index: 1000;"></ul>
                            </div>
                        </td>
                        <td class="tipo">-</td>
                        <td><input type="number" class="form-control cantidad" name="cantidad" step="0.01" min="0"></td>
                        <td><input type="text" class="form-control unidad" name="unidad" readonly></td>
                        <td><input type="number" class="form-control costo_total" name="costo_total" step="0.01" min="0"></td>
                    </tr>
                </tbody>
            </table>
       

        <p class="text-white"><strong>Total: $<span id="total">0.00</span></strong></p>

        <div class="form-group">
            <button type="button" id="agregarFila" class="btn custom-btn">Agregar producto</button>
            <button type="submit" id="btn-registrar" class="btn custom-btn" data-action="registrar-entrada">Registrar entrada</button>
        </div>
    </form>
    </div>
</div>
<div id="alert-sin-corte" class="container mt-5" style="<?= $__mostrar_registro_entrada ? 'display:none' : '';?>">
  <div class="alert alert-warning" role="alert">
    No hay un corte de almacén abierto. Abra un corte para habilitar "Registrar entrada de productos".
  </div>
</div>
<!-- insumo End -->

<!-- alerta stock-->
<div class="container mt-5">
    <h2 class="text-white">Insumos con bajo stock</h2>
    <div  class="d-flex align-items-center gap-2 mb-2" style="gap:.5rem;">
        <input type="text" id="buscarBajoStock" class="form-control" placeholder="Buscar en bajo stock" style="max-width:260px">
        <label for="bsPageSize" class="mb-0 ms-2 me-1 text-white">Ver</label>
        <select id="bsPageSize" class="form-control" style="max-width:100px">
            <option value="15">15</option>
            <option value="30">30</option>
            <option value="50">50</option>
        </select>
        <span class="text-white ms-1">registros</span>
    </div>
    <div class="table-responsive">
        <table style="color:black" id="bajoStock" class="styled-table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Nombre</th>
                    <th>Unidad</th>
                    <th>Existencia</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
    <ul id="bsPaginador" class="pagination justify-content-center mt-2"></ul>
</div>
<!-- alerta stock end -->

<div class="container mt-5">
    <h2 class="text-white">Historial de Entradas por Proveedor</h2>
    <div class="d-flex align-items-center gap-2 mb-2" style="gap:.5rem;">
        <input type="text" id="buscarHistorial" class="form-control" placeholder="Buscar en historial" style="max-width:260px">
        <label for="histPageSize" class="mb-0 ms-2 me-1 text-white">Ver</label>
        <select id="histPageSize" class="form-control" style="max-width:100px">
            <option value="15">15</option>
            <option value="30">30</option>
            <option value="50">50</option>
        </select>
        <span class="text-white ms-1">registros</span>
    </div>
    <div class="table-responsive">
                <table id="historial" class="styled-table">
            <thead>
                <tr>
                    <th>Proveedor</th>
                    <th>Fecha</th>
                    <th>Costo total</th>
                    <th>Cantidad actual</th>
                    <th>Total</th>
                    <th>Producto</th>
                    <th>Nota física</th>
                    <th>Folio fiscal</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
    <ul id="histPaginador" class="pagination justify-content-center mt-2"></ul>
</div>





<!-- Modal Nuevo Proveedor -->
<div class="modal fade" id="modalProveedor" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form id="formProveedor">
                <div class="modal-header">
                    <h5 style="color:black" class="modal-title">Nuevo Proveedor</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                </div>
                <div style="color:black" class="modal-body">
                    <div class="drag-container">
                        <div class="drag-column-header mb-2">Datos del proveedor</div>
                        <div class="container-fluid px-0">
                            <div class="row g-2">
                                <div class="col-sm-6 col-md-4">
                                    <label for="provNombre">Nombre</label>
                                    <input type="text" id="provNombre" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provTelefono">Teléfono</label>
                                    <input type="text" id="provTelefono" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provTelefono2">Teléfono 2</label>
                                    <input type="text" id="provTelefono2" class="form-control">
                                </div>

                                <div class="col-sm-6 col-md-4">
                                    <label for="provCorreo">Correo</label>
                                    <input type="email" id="provCorreo" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provRFC">RFC</label>
                                    <input type="text" id="provRFC" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provRazonSocial">Razón social</label>
                                    <input type="text" id="provRazonSocial" class="form-control">
                                </div>

                                <div class="col-sm-6 col-md-4">
                                    <label for="provRegimenFiscal">Régimen fiscal (SAT)</label>
                                    <input type="text" id="provRegimenFiscal" class="form-control" placeholder="601, 603, ...">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provCorreoFact">Correo facturación</label>
                                    <input type="email" id="provCorreoFact" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provDiasCredito">Días de crédito</label>
                                    <input type="number" id="provDiasCredito" class="form-control" value="0" min="0">
                                </div>

                                <div class="col-sm-6 col-md-4">
                                    <label for="provLimiteCredito">Límite de crédito</label>
                                    <input type="number" id="provLimiteCredito" class="form-control" value="0.00" step="0.01" min="0">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provBanco">Banco</label>
                                    <input type="text" id="provBanco" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provClabe">CLABE</label>
                                    <input type="text" id="provClabe" class="form-control" maxlength="18">
                                </div>

                                <div class="col-sm-6 col-md-4">
                                    <label for="provCuenta">Cuenta bancaria</label>
                                    <input type="text" id="provCuenta" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provSitioWeb">Sitio web</label>
                                    <input type="text" id="provSitioWeb" class="form-control">
                                </div>
                                <div class="col-12 col-md-8">
                                    <label for="provDireccion">Dirección</label>
                                    <input type="text" id="provDireccion" class="form-control">
                                </div>

                                <div class="col-sm-6 col-md-4">
                                    <label for="provContactoNombre">Contacto - Nombre</label>
                                    <input type="text" id="provContactoNombre" class="form-control">
                                </div>
                                <div class="col-sm-6 col-md-4">
                                    <label for="provContactoPuesto">Contacto - Puesto</label>
                                    <input type="text" id="provContactoPuesto" class="form-control">
                                </div>
                                <div class="col-12">
                                    <label for="provObservacion">Observación</label>
                                    <textarea id="provObservacion" class="form-control" rows="2"></textarea>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn custom-btn me-2" type="submit">Guardar</button>
                    <button class="btn custom-btn me-2" type="button" id="cancelarProveedor" data-dismiss="modal">Cancelar</button>
                </div>
            </form>
        </div>
    </div>
</div>
<!-- Modal Nuevo Proveedor End -->
<!-- Modal Resumen Entrada -->
<div class="modal fade" id="modalResumenEntrada" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 style="color:black" class="modal-title">Entradas registradas</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div style="color:black" class="modal-body">
                <p id="resumenEntradaMensaje" class="text-muted mb-3">Se generaron las siguientes entradas y códigos QR.</p>
                <div id="resumenEntradasLista" class="row gy-3"></div>
            </div>
            <div class="modal-footer d-flex align-items-center justify-content-between">
                <div class="print-controls me-2">
                    <label class="mb-1" for="selImpresoraResumen" style="color:black">Impresora</label>
                    <select id="selImpresoraResumen" class="sel-impresora form-select">
                        <option value="">(Selecciona impresora)</option>
                    </select>
                </div>
                <div class="ms-auto">
                    <button type="button" class="btn btn-secondary me-2" data-dismiss="modal">Cerrar</button>
                    <button type="button" class="btn custom-btn" id="btnImprimirResumen">Imprimir QRs</button>
                </div>
            </div>
        </div>
    </div>
</div>
<!-- Modal Resumen Entrada End -->
<!-- Modal global de mensajes -->
<div class="modal fade" id="appMsgModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div style="color:black" class="modal-content">
            <div class="modal-header">
                <h5 style="color:black" class="modal-title">Mensaje</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body"></div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
</div>

<!-- Modal Observación Proveedor -->
<div class="modal fade" id="modalProvObs" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content" style="color:black">
            <div class="modal-header">
                <h5 style="color:black" class="modal-title">Observación del proveedor</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body">
                <div id="provObsBox" style="max-height:60vh; overflow:auto; white-space:pre-wrap; line-height:1.35;"></div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
    </div>

<?php require_once __DIR__ . '/../footer.php'; ?>

<script src="../../utils/js/buscador.js"></script>
<script src="insumos.js" defer></script>
</body>

</html>

<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
