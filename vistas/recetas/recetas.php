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
$title = 'Recetas';
ob_start();
?>
<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Modulo de Recetas</h2>
            </div>
            <div class="col-12">
                <a href="">Inicio</a>
                <a href="">Catálogo de Recetas</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->

<div class="container mt-5 mb-5">
    <h1 class="section-header">Recetas de Platillos</h1>

    <div class="form-group">
        <label for="producto_id">Platillo:</label>
        <select id="producto_id" class="form-control"></select>
    </div>

    <div id="vistaProducto" class="product-view">
        <p id="nombreProducto" class="product-name"></p>
        <img id="imgProducto" class="product-image" alt="Imagen del producto">

        <form id="formImagen" style="display:none;" enctype="multipart/form-data">
            <div class="form-group">
                <label for="imagenProducto">Subir nueva imagen:</label>
                <input type="file" id="imagenProducto" accept="image/*" class="form-control-file">
            </div>
            <button type="button" id="subirImagen" class="btn custom-btn">Subir imagen</button>
        </form>
    </div>
</div>

<div class="container mt-5 mb-5">
  <h2 class="section-subheader">Ingredientes</h2>
  
  <div class="table-responsive">
    <table id="tablaReceta" class="styled-table">
      <thead>
        <tr>
          <th>Ingrediente</th>
          <th>Cantidad</th>
          <th>Unidad</th>
          <th>Acción</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><select class="form-control insumo"></select></td>
          <td><input type="number" step="0.01" class="form-control cantidad"></td>
          <td class="unidad">—</td>
          <td><button type="button" class="btn btn-sm btn-danger eliminar">Eliminar</button></td>
        </tr>
      </tbody>
    </table>
  </div>

  <div class="mb-3">
    <button type="button" id="agregarFila" class="btn custom-btn">Agregar insumo</button>
    <button type="button" id="guardarReceta" class="btn custom-btn">Guardar receta</button>
    <button type="button" id="copiarReceta" class="btn btn-secondary">Copiar receta de otro producto</button>
  </div>

  <!-- MODAL NORMALIZED 2025-08-14 -->
  <div class="modal fade" id="modalCopiarReceta" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title">Copiar receta</h5>
          <button type="button" class="close" data-dismiss="modal" aria-label="Close">
            <span aria-hidden="true">&times;</span>
          </button>
        </div>
        <div class="modal-body"><!-- contenido dinámico --></div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
        </div>
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
<script src="../../utils/js/modal-lite.js"></script>
<script src="recetas.js"></script>
    </body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
