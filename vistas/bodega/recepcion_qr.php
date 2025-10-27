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

require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';

$token = $_GET['token'] ?? '';
$mensaje = '';
$datos = [];
$pdf_recepcion = '';

if ($token !== '') {
    $stmt = $conn->prepare('SELECT * FROM qrs_insumo WHERE token = ?');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $qr = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$qr || $qr['estado'] !== 'pendiente') {
        $mensaje = 'QR inválido o ya procesado';
    } elseif ($qr['expiracion'] && strtotime($qr['expiracion']) < time()) {
        $mensaje = 'QR expirado';
    } else {
        $datos = json_decode($qr['json_data'], true);
    }
} else {
    $mensaje = 'QR inválido';
}

// Preparar datos del creador para mostrar en la vista
$creado_por_nombre = '';
if (!empty($qr) && isset($qr['creado_por'])) {
    $stInfo = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ? LIMIT 1');
    if ($stInfo) {
        $stInfo->bind_param('i', $qr['creado_por']);
        if ($stInfo->execute()) { $stInfo->bind_result($creado_por_nombre); $stInfo->fetch(); }
        $stInfo->close();
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !$mensaje && !empty($qr)) {
    $obs = trim($_POST['observaciones'] ?? '');
    $usuario_id = (int)($_SESSION['usuario_id'] ?? 0);

    // Validación de administrador: pedir y verificar contraseña de un usuario con rol 'admin'
    $admin_pass = isset($_POST['admin_pass']) ? trim((string)$_POST['admin_pass']) : '';
    $admin_id = 0; $admin_nombre = '';
    if ($admin_pass === '') {
        $mensaje = 'Debe ingresar la contraseña de un administrador para validar.';
    } else {
        if ($stAdm = $conn->prepare("SELECT id, nombre FROM usuarios WHERE rol='admin' AND contrasena = ? AND activo = 1 LIMIT 1")) {
            $stAdm->bind_param('s', $admin_pass);
            if ($stAdm->execute()) { $stAdm->bind_result($admin_id, $admin_nombre); $stAdm->fetch(); }
            $stAdm->close();
        }
        if (!$admin_id) {
            $mensaje = 'Contraseña de validación inválida o sin permisos de admin.';
        }
    }
    
    if ($mensaje) {
        // Evitar continuar si la validación de admin falló
        goto RENDER_FORM;
    }

    // Selección de BD de destino para insertar (opcional)
    $destKey = isset($_POST['dest_db']) ? trim($_POST['dest_db']) : '';
    $destPdo = null;
    if ($destKey !== '' && function_exists('cdi_pdo_by_key')) {
        $destPdo = cdi_pdo_by_key($destKey);
    }

    $usingLocal = !($destPdo instanceof PDO);
    try {
        if ($usingLocal) {
            // Inserción en BD actual
            $conn->begin_transaction();
            $upd = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
            $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, usuario_destino_id, insumo_id, cantidad, observacion, qr_token) VALUES ('entrada', ?, ?, ?, ?, ?, ?)");
            foreach ($datos as $d) {
                $cant = (float)$d['cantidad']; $iid = (int)$d['id'];
                $upd->bind_param('di', $cant, $iid);
                if (!$upd->execute()) throw new Exception($upd->error);

                $mov->bind_param('iiidss', $usuario_id, $qr['creado_por'], $iid, $cant, $obs, $token);
                if (!$mov->execute()) throw new Exception($mov->error);
            }
            $upd->close();
            $mov->close();
        } else {
            // Inserción en BD destino (PDO)
            $destPdo->beginTransaction();
            $stmtUpd = $destPdo->prepare('UPDATE insumos SET existencia = existencia + :cant WHERE id = :id');
            $stmtMov = $destPdo->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, usuario_destino_id, insumo_id, cantidad, observacion, qr_token) VALUES ('entrada', :uid, :uorig, :iid, :cant, :obs, :tok)");
            foreach ($datos as $d) {
                $stmtUpd->execute([':cant' => (float)$d['cantidad'], ':id' => (int)$d['id']]);
                $stmtMov->execute([
                    ':uid' => $usuario_id,
                    ':uorig' => (int)$qr['creado_por'],
                    ':iid' => (int)$d['id'],
                    ':cant' => (float)$d['cantidad'],
                    ':obs' => $obs,
                    ':tok' => $token,
                ]);
            }
            $destPdo->commit();
        }

        // Generar PDF y actualizar estado del QR (SIEMPRE en la BD actual)
        $dirPdf = __DIR__ . '/../../uploads/qrs';
        if (!is_dir($dirPdf)) { mkdir($dirPdf, 0777, true); }
        $pdf_recepcion = 'uploads/qrs/recepcion_' . $token . '.pdf';

        // Nombres de usuarios
        $stmtNombre = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
        $stmtNombre->bind_param('i', $qr['creado_por']);
        $stmtNombre->execute();
        $stmtNombre->bind_result($nombre_envia);
        $stmtNombre->fetch();
        $stmtNombre->close();

        $stmtNombre = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
        $stmtNombre->bind_param('i', $usuario_id);
        $stmtNombre->execute();
        $stmtNombre->bind_result($nombre_recibe);
        $stmtNombre->fetch();
        $stmtNombre->close();

        $lineas = [];
        $lineas[] = 'Fecha: ' . date('Y-m-d H:i');
        $lineas[] = 'Entregado por: ' . $nombre_envia;
        $lineas[] = 'Recibido por: ' . $nombre_recibe;
        if ($admin_nombre !== '') { $lineas[] = 'Validado por: ' . $admin_nombre; }
        if ($obs !== '') { $lineas[] = 'Observaciones: ' . $obs; }

        // Agrupar ítems por "reque" para imprimirlos en el PDF por secciones
        $orden_reque_pdf = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros',''];
        $ids_pdf = [];
        foreach ($datos as $d) { if (isset($d['id'])) { $ids_pdf[] = (int)$d['id']; } }
        $ids_pdf = array_values(array_unique(array_filter($ids_pdf, function($v){ return $v>0; })));
        $requeByIdPdf = [];
        if (!empty($ids_pdf)) {
            $in  = implode(',', array_fill(0, count($ids_pdf), '?'));
            $types = str_repeat('i', count($ids_pdf));
            if ($stmtRq = $conn->prepare("SELECT id, reque FROM insumos WHERE id IN ($in)")) {
                $stmtRq->bind_param($types, ...$ids_pdf);
                if ($stmtRq->execute()) {
                    $rsRq = $stmtRq->get_result();
                    while ($r = $rsRq->fetch_assoc()) { $requeByIdPdf[(int)$r['id']] = (string)$r['reque']; }
                }
                $stmtRq->close();
            }
        }
        $gruposPdf = [];
        foreach ($datos as $d) {
            $iid = isset($d['id']) ? (int)$d['id'] : 0;
            $rq  = $requeByIdPdf[$iid] ?? '';
            if (!isset($gruposPdf[$rq])) { $gruposPdf[$rq] = []; }
            $gruposPdf[$rq][] = $d;
        }
        // Imprimir por orden definido y luego cualquier otro grupo faltante
        $yaImp = [];
        $appendGrupo = function($cat) use (&$gruposPdf, &$lineas, &$yaImp) {
            $items = $gruposPdf[$cat] ?? [];
            if (!$items) return;
            $yaImp[$cat] = true;
            $lineas[] = ($cat !== '' ? $cat : 'Otros');
            usort($items, function($a,$b){ return strcasecmp((string)($a['nombre']??''), (string)($b['nombre']??'')); });
            foreach ($items as $d) {
                $lineas[] = ($d['nombre'] ?? '') . ' - ' . ($d['cantidad'] ?? '') . ' ' . ($d['unidad'] ?? '');
            }
        };
        foreach ($orden_reque_pdf as $cat) { $appendGrupo($cat); }
        foreach ($gruposPdf as $cat => $items) { if (!isset($yaImp[$cat])) { $appendGrupo($cat); } }

        generar_pdf_simple(__DIR__ . '/../../' . $pdf_recepcion, 'Recepción de insumos', $lineas);

        $upqr = $conn->prepare('UPDATE qrs_insumo SET estado = "confirmado", pdf_recepcion = ?, valida = ? WHERE id = ?');
        $upqr->bind_param('sii', $pdf_recepcion, $admin_id, $qr['id']);
        if (!$upqr->execute()) throw new Exception($upqr->error);
        $upqr->close();

        if ($usingLocal) { $conn->commit(); }
        $mensaje = 'Recepción registrada';
    } catch (Throwable $e) {
        if ($usingLocal && method_exists($conn, 'rollback')) { $conn->rollback(); }
        if ($destPdo instanceof PDO && $destPdo->inTransaction()) { $destPdo->rollBack(); }
        $mensaje = 'Error al registrar recepción';
    }
}

$title = 'Recepción QR';
ob_start();
RENDER_FORM:
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Modulo de CDI</h2>
            </div>
            <div class="col-12">
                <a href="">Inicio</a>
                <a href="">Catálogo de recepción en tienda</a>
            </div>
        </div>
    </div>
    </div>
<div class="container mt-4">
    <h2 class="text-white">Recepción de insumos</h2>
    <?php if ($mensaje): ?>
        <p class="text-white"><?= htmlspecialchars($mensaje) ?></p>
        <?php
        // Mostrar botón Nota entrada cuando ya se generó el PDF
        if ($mensaje && ($pdf_recepcion || $token)) {
            $recPath = $pdf_recepcion ?: ('uploads/qrs/recepcion_' . $token . '.pdf');
            echo '<a class="btn custom-btn" href="../../' . htmlspecialchars($recPath) . '" target="_blank">Nota entrada</a>';
        }
        ?>
    <?php endif; ?>

    <?php if ($datos && !$mensaje): ?>
        <form method="post">
            <div class="mb-3">
                <label class="text-white" for="dest_db">Insertar en BD</label>
                <select class="form-select" name="dest_db" id="dest_db">
                    <option value="">BD actual (esta)</option>
                    <?php if (isset($CDI_DB_OPTIONS) && is_array($CDI_DB_OPTIONS)): foreach ($CDI_DB_OPTIONS as $k=>$opt): if (!empty($opt['pdo'])): ?>
                        <option value="<?= htmlspecialchars($k) ?>"><?= htmlspecialchars($opt['label'] ?? $k) ?></option>
                    <?php endif; endforeach; endif; ?>
                </select>
            </div>
            <div class="table-responsive">
                <table class="styled-table">
                    <thead>
                        <tr>
                            <th>Insumo</th>
                            <th>Cantidad</th>
                            <th>Unidad</th>
                        </tr>
                    </thead>
                    <tbody>
<?php
// Agrupar la recepcion por reque
$orden_reque = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros',''];
$ids = [];
foreach ($datos as $d) { if (isset($d['id'])) { $ids[] = (int)$d['id']; } }
$ids = array_values(array_unique(array_filter($ids, function($v){ return $v>0; })));
$requeById = [];
if (!empty($ids)) {
    $in  = implode(',', array_fill(0, count($ids), '?'));
    $types = str_repeat('i', count($ids));
    if ($stmt = $conn->prepare("SELECT id, reque FROM insumos WHERE id IN ($in)")) {
        $stmt->bind_param($types, ...$ids);
        if ($stmt->execute()) {
            $rs = $stmt->get_result();
            while ($r = $rs->fetch_assoc()) { $requeById[(int)$r['id']] = (string)$r['reque']; }
        }
        $stmt->close();
    }
}
$grupos = [];
foreach ($datos as $d) {
    $iid = isset($d['id']) ? (int)$d['id'] : 0;
    $rq  = $requeById[$iid] ?? '';
    if (!isset($grupos[$rq])) { $grupos[$rq] = []; }
    $grupos[$rq][] = $d;
}
foreach ($orden_reque as $cat) {
    $items = $grupos[$cat] ?? [];
    if (!$items) continue;
    echo '<tr><td colspan="3" style="font-weight:bold; background:#222; color:#fff; text-align:center;">'.htmlspecialchars($cat).'</td></tr>';
    usort($items, function($a,$b){ return strcasecmp((string)($a['nombre']??''), (string)($b['nombre']??'')); });
    foreach ($items as $d) {
        echo '<tr>';
        echo '<td>'.htmlspecialchars($d['nombre']).'</td>';
        echo '<td>'.htmlspecialchars((string)$d['cantidad']).'</td>';
        echo '<td>'.htmlspecialchars($d['unidad']).'</td>';
        echo '</tr>';
    }
}
?>
                    </tbody>
                </table>
            </div>
            <div class="mb-3">
                <label class="text-white">Observaciones:</label>
                <textarea name="observaciones" class="form-control"></textarea>
            </div>
            <div class="mb-3">
                <label class="text-white">Contraseña Admin para validar:</label>
                <input type="password" name="admin_pass" class="form-control" required>
            </div>
            <button type="submit" class="btn custom-btn">Aceptar entrega</button>
            <?php if ($pdf_recepcion): ?>
                <a class="btn custom-btn" href="../../<?= $pdf_recepcion ?>" target="_blank">Ver PDF</a>
            <?php endif; ?>
            </form>

            <?php if (!empty($qr) && !$mensaje): ?>
            <div class="mt-3">
                <h5 class="text-white">Información del QR</h5>
                <div class="card p-3" style="color:black">
                    <div><strong>Generado por:</strong> <?= htmlspecialchars($creado_por_nombre ?: '') ?></div>
                    <div><strong>Fecha de creación:</strong> <?= isset($qr['creado_en']) && $qr['creado_en'] ? date('Y-m-d H:i', strtotime($qr['creado_en'])) : '' ?></div>
                    <div><strong>Estado:</strong> <?= htmlspecialchars($qr['estado'] ?? '') ?></div>
                    <div class="mt-2">
                        <a class="btn custom-btn" href="../../api/bodega/qr_pdf.php?token=<?= urlencode($token) ?>" target="_blank">Reimprimir PDF de envío</a>
                    </div>
                </div>
            </div>
            <?php endif; ?>
    <?php endif; ?>

    <?php if (!empty($qr) && !$mensaje): ?>
      <div class="mt-3">
        <div class="table-responsive">
          <table class="styled-table" id="tblResumen">
            <thead>
              <tr><th>Insumo</th><th>Unidad</th><th>Enviado</th><th>Devuelto</th><th>Pendiente</th><th>Devolver</th></tr>
            </thead>
            <tbody></tbody>
          </table>
        </div>
        <div class="my-2 d-flex gap-2">
          <button class="btn custom-btn" id="btnDevTodo">Devolver todo</button>
          <button class="btn custom-btn" id="btnDevParcial">Confirmar devolución parcial</button>
          <button class="btn custom-btn" id="btnVerQrsDevol">Ver QRs de devolución</button>
        </div>
      </div>
    <?php endif; ?>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
<?php if (!empty($qr) && !$mensaje): ?>
<div id="modalDevObs" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.45); z-index:10000;">
  <div style="max-width:560px; margin:60px auto; background:#fff; border-radius:6px; overflow:hidden;">
    <div style="padding:12px 16px; background:#f3f3f3; border-bottom:1px solid #ddd;">
    </div>
    <div style="padding:16px;">
      <textarea id="txtDevObs" class="form-control" rows="4" placeholder="Escribe una observación opcional..."></textarea>
      <div class="d-flex justify-content-end gap-2 mt-3">
        <button type="button" id="btnDevObsCancelar" class="btn btn-secondary">Cancelar</button>
        <button type="button" id="btnDevObsConfirmar" class="btn custom-btn">Confirmar</button>
      </div>
    </div>
  </div>
</div>

<div id="modalDevQrs" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.45); z-index:10000;">
  <div style="max-width:900px; margin:60px auto; background:#fff; border-radius:6px; overflow:hidden;">
    <div style="padding:12px 16px; background:#f3f3f3; border-bottom:1px solid #ddd; display:flex; justify-content:space-between; align-items:center;">
      <button type="button" id="btnCerrarDevQrs" class="btn custom-btn-sm">Cerrar</button>
    </div>
    <div style="padding:12px; max-height:70vh; overflow:auto;">
      <div class="d-flex justify-content-end align-items-center mb-2" style="gap:8px;">
        <label style="margin:0; color:#333; font-weight:600;">Impresora</label>
        <select id="selDevPrinters" class="form-select form-select-sm sel-impresora" style="max-width:260px">
          <option value="">(Selecciona impresora)</option>
        </select>
      </div>
      <div id="listaDevQrs" class="row g-3"></div>
    </div>
  </div>
</div>

<script>
const token = <?= json_encode($token) ?>;
async function cargarResumen(){
  const resp = await fetch('../../api/bodega/qr_resumen.php?token='+encodeURIComponent(token));
  const json = await resp.json();
  if(!json.success){ alert(json.mensaje||'Error'); return; }
  const tbody = document.querySelector('#tblResumen tbody');
  tbody.innerHTML = '';
  const orden = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros'];
  const grupos = {};
  (json.resultado.items||[]).forEach(it=>{
    const cat = it.reque || '';
    if (!grupos[cat]) grupos[cat] = [];
    grupos[cat].push(it);
  });
  orden.forEach(cat => {
    const arr = grupos[cat] || [];
    if (!arr.length) return;
    const th = document.createElement('tr');
    th.innerHTML = `<td colspan="6" style="font-weight:bold; background:#222; color:#fff; text-align:center;">${cat}</td>`;
    tbody.appendChild(th);
    arr.sort((a,b)=> String(a.nombre||'').localeCompare(String(b.nombre||''), undefined, { sensitivity: 'base' }));
    arr.forEach(it=>{
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${it.nombre}</td><td>${it.unidad||''}</td>
        <td class="text-end">${Number(it.enviado||0).toFixed(2)}</td>
        <td class="text-end">${Number(it.devuelto||0).toFixed(2)}</td>
        <td class="text-end">${Number(it.pendiente||0).toFixed(2)}</td>
        <td><input type=\"number\" min=\"0\" step=\"0.01\" data-insumo=\"${it.insumo_id}\" class=\"form-control form-control-sm inpDev\" placeholder=\"0.00\"></td>`;
      tbody.appendChild(tr);
    });
  });
}

// Estado y helpers de modal de observación de devolución
let devCtx = { modo: 'total', items: [] };
function abrirModalDevObs(modo, items){
  try { devCtx = { modo, items: Array.isArray(items) ? items : [] }; } catch(_) { devCtx = { modo, items: [] }; }
  const t = document.getElementById('txtDevObs');
  if (t) t.value = '';
  const m = document.getElementById('modalDevObs');
  if (m) m.style.display = '';
}


// document.getElementById('btnDevParcial')?.addEventListener('click', async ()=>{
  // const items = Array.from(document.querySelectorAll('.inpDev'))
    // .map(inp=>({ insumo_id: parseInt(inp.dataset.insumo), cantidad: parseFloat(inp.value||'0') }))
    // .filter(x=>x.insumo_id>0 && x.cantidad>0);
function cerrarModalDevObs(){ const m=document.getElementById('modalDevObs'); if (m) m.style.display='none'; }
async function confirmarModalDevObs(){
  const obs = (document.getElementById('txtDevObs')?.value || '').trim();
  const payload = devCtx.modo === 'parcial' ? { modo:'parcial', items: devCtx.items, observacion: obs } : { modo:'total', observacion: obs };
  const resp = await fetch('../../api/bodega/qr_devoluciones.php?token='+encodeURIComponent(token), { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload) });
  const json = await resp.json();
  if(!json.success){ alert(json.mensaje||'Error'); return; }
  cerrarModalDevObs();
  cargarResumen();
}
document.getElementById('btnDevObsCancelar')?.addEventListener('click', cerrarModalDevObs);
document.getElementById('btnDevObsConfirmar')?.addEventListener('click', confirmarModalDevObs);

// Capturing listeners para reemplazar prompts por modal
document.getElementById('btnDevTodo')?.addEventListener('click', (e)=>{ e.preventDefault(); e.stopPropagation(); abrirModalDevObs('total', []); }, true);
document.getElementById('btnDevParcial')?.addEventListener('click', (e)=>{
  e.preventDefault(); e.stopPropagation();
  const items = Array.from(document.querySelectorAll('.inpDev'))
    .map(inp=>({ insumo_id: parseInt(inp.dataset.insumo), cantidad: parseFloat(inp.value||'0') }))
    .filter(x=>x.insumo_id>0 && x.cantidad>0);
  if(items.length===0){ alert('Ingresa cantidades a devolver'); return; }
  abrirModalDevObs('parcial', items);
}, true);

async function abrirModalDevQrs(){
  const modal = document.getElementById('modalDevQrs');
  const cont = document.getElementById('listaDevQrs');
  if (!modal || !cont) return;
  cont.innerHTML = '<div class="col-12">Cargando...</div>';
  modal.style.display = '';
  try {
    const resp = await fetch('../../api/bodega/qr_devolucion_qrs.php?token='+encodeURIComponent(token));
    const json = await resp.json();
    if (!json.success){ cont.innerHTML = '<div class="col-12">Error al cargar</div>'; return; }
    const qrs = (json.resultado && json.resultado.qrs) ? json.resultado.qrs : [];
    cont.innerHTML = '';
    qrs.forEach(q => {
      const col = document.createElement('div');
      col.className = 'col-sm-6 col-md-4';
      const imgSrc = '../../' + q.qr;
      col.innerHTML = `
        <div style="border:1px solid #ddd; border-radius:6px; padding:8px; text-align:center; background:#fafafa;">
          <div style=\"font-weight:600; margin-bottom:6px; color:#333;\">${q.insumo || ''}</div>
          <img src=\"${imgSrc}\" alt=\"QR ${q.id_entrada}\" style=\"max-width:100%; height:auto;\"/>
          <div style=\"font-size:12px; color:#555; margin-top:6px;\">Entrada #${q.id_entrada} | ${q.fecha ? new Date(q.fecha).toLocaleString() : ''}</div>
          <div style=\"font-size:12px; color:#555;\">Devuelto: ${Number(q.devuelto||0).toFixed(2)} ${q.unidad||''}</div>
          <div class=\"mt-1\"><button type=\"button\" class=\"btn custom-btn-sm btn-print-devqr\" data-entrada-id=\"${q.id_entrada}\">Imprimir</button></div>
        </div>`;
      cont.appendChild(col);
    });
  } catch (e) {
    cont.innerHTML = '<div class="col-12">Error al cargar</div>';
  }
}
document.getElementById('btnVerQrsDevol')?.addEventListener('click', abrirModalDevQrs);
document.getElementById('btnCerrarDevQrs')?.addEventListener('click', ()=>{ const m=document.getElementById('modalDevQrs'); if(m) m.style.display='none'; });

cargarResumen();

// Cargar impresoras en el combo del modal y manejar impresión
async function cargarImpresorasEnDev(){
  try{
    const sel = document.getElementById('selDevPrinters');
    if (!sel) return;
    sel.innerHTML = '<option value="">(Selecciona impresora)</option>';
    const r = await fetch('/rest2/CDI/api/impresoras/listar.php', { cache: 'no-store' });
    const j = await r.json();
    const data = (j && (j.resultado || j.data)) || [];
    (data||[]).forEach(p=>{
      const opt = document.createElement('option');
      opt.value = p.ip;
      opt.textContent = ((p.lugar||'') + ' - ' + p.ip).trim();
      sel.appendChild(opt);
    });
  }catch(e){ /* noop */ }
}

// Hook: al abrir modal, cargar impresoras y delegar clicks de imprimir
try{ document.getElementById('btnVerQrsDevol')?.addEventListener('click', cargarImpresorasEnDev); }catch(_){ }
try{
  document.getElementById('listaDevQrs')?.addEventListener('click', async (ev)=>{
    const btn = ev.target.closest('.btn-print-devqr');
    if (!btn) return;
    const entradaId = parseInt(btn.getAttribute('data-entrada-id')||'0', 10);
    if (!Number.isFinite(entradaId) || entradaId <= 0) { alert('Entrada inválida'); return; }
    const sel = document.getElementById('selDevPrinters');
    let url = '../../api/insumos/imprimir_qrs_entrada.php';
    if (sel && sel.value) { url += ('?printer_ip=' + encodeURIComponent(sel.value)); }
    try{
      btn.disabled = true; const old = btn.textContent; btn.textContent = 'Imprimiendo...';
      const resp = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'same-origin', body: JSON.stringify({ entrada_ids: [entradaId] }) });
      const payload = await resp.json();
      if (!payload || payload.success !== true) { throw new Error((payload && payload.mensaje) ? payload.mensaje : 'No se pudo imprimir'); }
      alert('Impresión enviada');
      btn.textContent = old; btn.disabled = false;
    }catch(err){ console.error(err); alert('Error al imprimir: ' + (err?.message||err)); btn.disabled=false; }
  });
}catch(_){ }
</script>
<?php endif; ?>

