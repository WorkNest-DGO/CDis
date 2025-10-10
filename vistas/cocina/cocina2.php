<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Constante de producto de envío (para UI si se requiere)
if (!defined('ENVIO_CASA_PRODUCT_ID')) define('ENVIO_CASA_PRODUCT_ID', 9001);
// Producto de cargo por plataforma (ocultar y auto-entregar)
if (!defined('CARGO_PLATAFORMA_PRODUCT_ID')) define('CARGO_PLATAFORMA_PRODUCT_ID', 9000);
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
$title = 'Cocina (Kanban)';
$rol_usuario = $_SESSION['rol'] ?? ($_SESSION['usuario']['rol'] ?? '');
// Si no hay rol en sesión, consultarlo desde BD
if ($rol_usuario === '' || $rol_usuario === null) {
    $uid = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
    if ($uid > 0) {
        $stmtRU = $conn->prepare('SELECT rol FROM usuarios WHERE id = ? LIMIT 1');
        if ($stmtRU) {
            $stmtRU->bind_param('i', $uid);
            if ($stmtRU->execute()) {
                $resRU = $stmtRU->get_result();
                if ($resRU && ($rowRU = $resRU->fetch_assoc())) {
                    $rol_usuario = (string)$rowRU['rol'];
                    $_SESSION['rol'] = $rol_usuario; // persistir en sesión
                }
            }
            $stmtRU->close();
        }
    }
}
// Visibilidad de toolbar: solo admin y supervisor
$__rol_lower = strtolower((string)$rol_usuario);
$__puede_toolbar = in_array($__rol_lower, ['admin','supervisor'], true);

// Validar corte de almacén abierto para mostrar la sección "Crear lote"
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
    // Si falla la consulta, tratar como si no hubiera corte abierto
    $__corte_id_abierto = 0;
}
$__mostrar_toolbar = $__puede_toolbar && ($__corte_id_abierto > 0);
ob_start();
?>
<div id="user-info" data-rol="<?= htmlspecialchars($rol_usuario, ENT_QUOTES); ?>" hidden></div>
<div id="corte-info" data-corte-id="<?= (int)$__corte_id_abierto; ?>" hidden></div>
<div id="corte-info" data-corte-id="<?= (int)$__corte_id_abierto; ?>" hidden></div>
<div class="page-header mb-0">
  <div class="container">
    <div class="row"><div class="col-12"><h2>Módulo de Cocina (Kanban)</h2></div></div>
  </div>
</div>

<div class="container my-3">
  <div class="d-flex gap-2 align-items-center flex-wrap">
    <input id="txtFiltro" type="text" class="form-control" placeholder="Filtrar por producto/destino" style="max-width:280px">
    <select id="selTipoEntrega" class="form-control" style="max-width:180px">
      <option value="">Todos</option>
      <option value="mesa">Mesa</option>
      <option value="domicilio">Domicilio</option>
      <option value="rapido">Rápido</option>
    </select>
    <button id="btnRefrescar" class="btn custom-btn">Refrescar</button>
  </div>
 </div>


<style>
/* Toolbar de procesado */
.procesado-toolbar{
  display:grid;
  grid-template-columns: repeat(4, minmax(160px, 1fr));
  gap:.5rem 1rem;
  align-items:end;
}
@media (max-width: 768px){
  .procesado-toolbar{ grid-template-columns: repeat(2, minmax(140px, 1fr)); }
}
.procesado-toolbar label{ font-weight:600; margin-bottom:0; }

/* Estilos Kanban (alineados al módulo rest) */
.kanban-container { display:grid; gap:12px; grid-template-columns: repeat(4, minmax(0, 1fr)); padding: 0 16px 24px; }
@media (max-width: 1200px){ .kanban-container { grid-template-columns: repeat(2, 1fr);} }
@media (max-width: 700px){ .kanban-container { grid-template-columns: 1fr;} }
.kanban-board { background:#fff; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,.08); display:flex; flex-direction:column; min-height: 65vh; }
.kanban-board h3 { margin:0; padding:12px 14px; font-size:16px; font-weight:700; color:#222; border-bottom:1px solid #eee; border-top-left-radius:10px; border-top-right-radius:10px; }
.kanban-dropzone { flex:1; padding:10px; min-height:200px; overflow:auto; }
.kanban-item { background:#fafafa; border:1px solid #e9e9e9; border-left:4px solid transparent; border-radius:8px; padding:10px; margin-bottom:8px; cursor:grab; }
.kanban-item:active { cursor:grabbing; }
.kanban-item .title { font-weight:600; line-height:1.2; color:#0a0a0a;}
.kanban-item .meta { font-size:12px; color:#666; display:flex; gap:10px; flex-wrap:wrap; margin-top:6px; }
.drag-over { outline:2px dashed #999; outline-offset:-6px; }
/* Colores por estado */
.board-pendiente h3 { background:#f17f15; border-color:#ffd4d4; }
.board-pendiente .kanban-item { border-left-color:#e74c3c; }
.board-preparacion h3 { background:#c6ee50; border-color:#ffd9a6; }
.board-preparacion .kanban-item { border-left-color:#a8f312; }
.board-listo h3 { background:#13ec74; border-color:#c8f0d9; }
.board-listo .kanban-item { border-left-color:#27ae60; }
.board-entregado h3 { background:#f5f5f5; border-color:#e5e5e5; }
.board-entregado .kanban-item { border-left-color:#7f8c8d; opacity:.85; }
.merma-qr-grid { display:flex; flex-wrap:wrap; gap:8px; margin-top:6px; }
.merma-qr-item { display:flex; flex-direction:column; align-items:center; gap:6px; border:1px solid #e0e0e0; border-radius:6px; padding:6px; background:#fff; min-width:120px; }
.merma-qr-item a { display:inline-flex; border-radius:4px; overflow:hidden; }
.merma-qr-item img { max-width:120px; height:auto; display:block; }
.merma-qr-item button { width:100%; }
.merma-section h6 { font-weight:600; margin-bottom:6px; }
</style>

<div id="sec-crear-grupo" class="container my-3" style="<?= ($__puede_toolbar && $__corte_id_abierto>0) ? '' : 'display:none'; ?>">
  <div class="procesado-toolbar" style="grid-template-columns: 1fr 1fr 1fr 1fr;">
    <label>Orígenes</label>
    <div style="grid-column: 1 / -1;">
      <div id="origenesContainer"></div>
      <button id="btnAddOrigen" class="btn btn-secondary btn-sm mt-2">Agregar origen</button>
    </div>

    <label for="selInsumoDestinoGrupo">Destino</label>
    <select id="selInsumoDestinoGrupo" class="form-control"></select>

    <label for="inpObsProcGrupo">Observaciones</label>
    <input id="inpObsProcGrupo" type="text" class="form-control" placeholder="Observaciones (opcional)">

    <button id="btnCrearGrupo" class="btn custom-btn" style="grid-column: 1 / -1;">Crear grupo</button>
  </div>
</div>
<div id="alert-sin-corte-lote" class="container my-3" style="<?= ($__corte_id_abierto <= 0) ? '' : 'display:none'; ?>">
  <div class="alert alert-warning" role="alert">
    No hay un corte de almacén abierto. Abra un corte para habilitar "Crear lote".
  </div>
</div>

<div id="kanban" class="kanban-container">
  <div class="kanban-board board-pendiente" data-status="pendiente">
    <h3>Pendiente</h3>
    <div class="kanban-dropzone" id="col-pendiente"></div>
  </div>
  <div class="kanban-board board-preparacion" data-status="en_preparacion">
    <h3>En preparación</h3>
    <div class="kanban-dropzone" id="col-preparacion"></div>
  </div>
  <div class="kanban-board board-listo" data-status="listo">
    <h3>Listo</h3>
    <div class="kanban-dropzone" id="col-listo"></div>
  </div>
  <div class="kanban-board board-entregado" data-status="entregado">
    <h3>Entregado</h3>
    <div class="kanban-dropzone" id="col-entregado"></div>
  </div>
</div>
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
<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="cocina2.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
