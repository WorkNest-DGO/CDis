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
$title = 'Inventario';
ob_start();
?>
<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Modulo de Platillos</h2>
            </div>
            <div class="col-12">
                <a href="">Inicio</a>
                <a href="">Inventario de Platillos</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->

<div class="container mt-5 mb-5">
  <h1 class="section-header">Inventario</h1>

  <div class="mb-3 text-end">
    <button class="btn custom-btn" id="agregarProducto">Agregar producto</button>
  </div>
  <div class="row mt-3">
    <div class="col-12">
      <ul id="paginadorInv" class="pagination justify-content-center"></ul>
    </div>
  </div>
  <div class="table-responsive">
    <table id="tablaProductos" class="styled-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Nombre</th>
          <th>Precio</th>
          <th>Existencia</th>
          <th>Descripción</th>
          <th>Activo</th>
          <th>Acciones</th>
        </tr>
      </thead>
      <tbody></tbody>
    </table>
  </div>

</div>

<!-- MODAL NORMALIZED 2025-08-14 -->
<div class="modal fade" id="modalAgregar" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form id="formAgregar">
        <div class="modal-header">
          <h5 class="modal-title">Agregar Producto</h5>
          <button type="button" class="close" onclick="cerrarModalAgregar()" aria-label="Close">
            <span aria-hidden="true">&times;</span>
          </button>
        </div>
        <div class="modal-body">
          <div class="form-group">
            <label for="nombreProducto">Nombre:</label>
            <input type="text" id="nombreProducto" class="form-control" required>
          </div>
          <div class="form-group">
            <label for="precioProducto">Precio:</label>
            <input type="number" step="0.01" id="precioProducto" class="form-control" required>
          </div>
          <div class="form-group">
            <label for="descripcionProducto">Descripción:</label>
            <textarea id="descripcionProducto" class="form-control"></textarea>
          </div>
          <div class="form-group">
            <label for="existenciaProducto">Existencia:</label>
            <input type="number" id="existenciaProducto" class="form-control" required>
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn custom-btn" type="submit">Guardar</button>
          <button class="btn custom-btn" type="button" onclick="cerrarModalAgregar()">Cancelar</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- MODAL NORMALIZED 2025-08-14 -->
<div class="modal fade" id="modalAlerta" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="modalTitulo">Resultado</h5>
        <button type="button" class="close" data-dismiss="modal" aria-label="Close">
          <span aria-hidden="true">&times;</span>
        </button>
      </div>
      <div class="modal-body">
        <p id="mensajeModal"></p>
      </div>
      <div class="modal-footer">
        <button class="btn custom-btn" data-dismiss="modal">Aceptar</button>
      </div>
    </div>
  </div>
</div>

<!-- MODAL NORMALIZED 2025-08-14 -->
<div class="modal fade" id="modalConfirmacion" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered" role="document">
    <div class="modal-content custom-modal">
      <div class="modal-body text-center">
        <p class="mensaje mb-0">¡Cambiado exitosamente!</p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn custom-btn" data-dismiss="modal">Aceptar</button>
      </div>
    </div>
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
<script src="inventario.js"></script>

<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
