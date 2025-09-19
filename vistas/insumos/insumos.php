<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Base app dinÇ­mica y ruta relativa para validaciï¿½ï¿½n
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
                <div class="modal-content">
                    <form id="formInsumo">
                        <div class="modal-header">
                            <h5 class="modal-title">Insumo</h5>
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
                                <input type="number" step="0.01" id="existencia" class="form-control" value="0">
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
<div class="container mt-5">
    <h2 class="text-white">Registrar entrada de productos</h2>
    <form id="form-entrada" class="bg-dark p-4 rounded" name="form-entrada">
        <div class="form-group">
            <label for="proveedor" class="text-white">Proveedor:</label>
            <select id="proveedor" name="proveedor_id" class="form-control"></select>
            <button type="button" id="btnNuevoProveedor" class="btn custom-btn mt-2">Nuevo proveedor</button>
        </div>

        <div class="table-responsive">
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
                        <td><select class="form-control insumo_id" name="insumo_id"></select></td>
                        <td class="tipo">-</td>
                        <td><input type="number" class="form-control cantidad" name="cantidad" step="0.01" min="0"></td>
                        <td><input type="text" class="form-control unidad" name="unidad" readonly></td>
                        <td><input type="number" class="form-control costo_total" name="costo_total" step="0.01" min="0"></td>
                    </tr>
                </tbody>
            </table>
        </div>

        <p class="text-white"><strong>Total: $<span id="total">0.00</span></strong></p>

        <div class="form-group">
            <button type="button" id="agregarFila" class="btn custom-btn">Agregar producto</button>
            <button type="submit" id="btn-registrar" class="btn custom-btn" data-action="registrar-entrada">Registrar entrada</button>
        </div>
    </form>
</div>
<!-- insumo End -->

<!-- alerta stock-->
<div class="container mt-5">
    <h2 class="text-white">Insumos con bajo stock</h2>
    <div class="table-responsive">
        <table id="bajoStock" class="styled-table">
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
</div>
<!-- alerta stock end -->

<div class="container mt-5">
    <h2 class="text-white">Historial de Entradas por Proveedor</h2>
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
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
</div>





<!-- Modal Nuevo Proveedor -->
<div class="modal fade" id="modalProveedor" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form id="formProveedor">
                <div class="modal-header">
                    <h5 class="modal-title">Nuevo Proveedor</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                </div>
                <div class="modal-body">
                    <div class="drag-container">
                        <ul class="drag-list">
                            <li class="drag-column">
                                <div class="drag-column-header">Datos del proveedor</div>
                                <ul class="drag-inner-list">
                                    <li class="drag-item">
                                        <label class="drag-options-label" for="provNombre">Nombre:
                                            <input type="text" id="provNombre" class="form-control">
                                        </label>
                                        <label class="drag-options-label" for="provTelefono">TelÇ¸fono:
                                            <input type="text" id="provTelefono" class="form-control">
                                        </label>
                                        <label class="drag-options-label" for="provDireccion">Direcciï¿½ï¿½n:
                                            <input type="text" id="provDireccion" class="form-control">
                                        </label>
                                    </li>
                                </ul>
                            </li>
                        </ul>
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
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
                <button type="button" class="btn custom-btn" id="btnImprimirResumen">Imprimir QRs</button>
            </div>
        </div>
    </div>
</div>
<!-- Modal Resumen Entrada End -->
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

<script src="insumos.js" defer></script>
</body>

</html>

<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>


