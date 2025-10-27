<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Validar acceso por ruta
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

$title = 'Historial de QRs';
ob_start();
?>
<div class="page-header mb-0">
  <div class="container">
    <div class="row">
      <div class="col-12"><h2>Modulo de CDI</h2></div>
      <div class="col-12"><a href="">Inicio</a><a href="">Historial de QRs</a></div>
    </div>
  </div>
  </div>
<div class="container mt-4">
  <h2 class="text-white">Historial de QRs</h2>
  <div class="row g-2 align-items-end">
    <div class="col-md-2">
      <label class="text-white">Fecha inicio</label>
      <input type="date" id="f_ini" class="form-control">
    </div>
    <div class="col-md-2">
      <label class="text-white">Fecha fin</label>
      <input type="date" id="f_fin" class="form-control">
    </div>
    <div class="col-md-2">
      <label class="text-white">Estado</label>
      <select id="estado" class="form-select">
        <option value="todos">Todos</option>
        <option value="pendiente">Pendiente</option>
        <option value="confirmado">Confirmado</option>
        <option value="anulado">Anulado</option>
      </select>
    </div>
    <div class="col-md-2">
      <label class="text-white">Token</label>
      <input type="text" id="token" class="form-control" placeholder="token">
    </div>
    <div class="col-md-3">
      <label class="text-white">Insumo</label>
      <input type="text" id="insumo" class="form-control" placeholder="Buscar insumo">
    </div>
    <div class="col-md-1">
      <button id="btnBuscar" class="btn custom-btn w-100">Buscar</button>
    </div>
  </div>

  <div class="table-responsive mt-3">
    <table class="styled-table" id="tabla">
      <thead>
        <tr>
          <th>Folio</th>
          <th>Token</th>
          <th>Fecha</th>
          <th>Usuario</th>
          <th>Estado</th>
          <th>#Items</th>
          <th>Acciones</th>
        </tr>
      </thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
  <div class="d-flex justify-content-center my-2">
    <button type="button" id="prevPag" class="btn custom-btn me-2">Anterior</button>
    <button type="button" id="nextPag" class="btn custom-btn">Siguiente</button>
  </div>
</div>

<script>
const qs = (sel)=>document.querySelector(sel);
const qsa = (sel)=>Array.from(document.querySelectorAll(sel));
let page = 1, per_page = 20, total = 0;

function fmtToken(t){ return t ? String(t).slice(0,8) : ''; }
function fmtDate(d){ return d ? new Date(d).toLocaleString() : ''; }

function setDefaultDates(){
  const hoy = new Date();
  const fin = hoy.toISOString().substring(0,10);
  const ini = new Date(hoy.getTime() - 6*24*60*60*1000).toISOString().substring(0,10);
  qs('#f_ini').value = ini;
  qs('#f_fin').value = fin;
}

async function cargar(){
  const params = new URLSearchParams();
  params.set('page', page);
  params.set('per_page', per_page);
  if(qs('#token').value.trim()!=='') params.set('token', qs('#token').value.trim());
  params.set('estado', qs('#estado').value);
  if(qs('#f_ini').value) params.set('fecha_ini', qs('#f_ini').value);
  if(qs('#f_fin').value) params.set('fecha_fin', qs('#f_fin').value);
  if(qs('#insumo').value.trim()!=='') params.set('insumo', qs('#insumo').value.trim());

  const resp = await fetch('../../api/bodega/qrs_list.php?' + params.toString());
  const json = await resp.json();
  if(!json.success){ alert(json.mensaje || 'Error'); return; }
  const { data, total:tot, page:pg, per_page:pp } = json.resultado;
  total = tot; page = pg; per_page = pp;
  renderRows(data);
}

function renderRows(rows){
  const tbody = qs('#tbody');
  tbody.innerHTML = '';
  rows.forEach(r => {
    const tr = document.createElement('tr');
    const notaBtn = (String(r.estado||'') === 'confirmado') ? `<button class="btn custom-btn btn-sm" data-act="nota" data-token="${r.token}" data-pdf-rec="${r.pdf_recepcion||''}">Nota entrada</button>` : '';
    tr.innerHTML = `
      <td>${r.id}</td>
      <td>${fmtToken(r.token)}</td>
      <td>${fmtDate(r.creado_en)}</td>
      <td>${r.creado_por_nombre || ''}</td>
      <td>${r.estado || ''}</td>
      <td>${r.items_count}</td>
      <td>
        <button class="btn custom-btn btn-sm" data-act="ver" data-token="${r.token}">Ver detalle</button>
        <button class="btn custom-btn btn-sm" data-act="reimp" data-token="${r.token}">Reimprimir</button>
        <button class="btn custom-btn btn-sm" data-act="pdf" data-token="${r.token}" data-pdf="${r.pdf_envio || ''}">Descargar PDF</button>
        ${notaBtn}
      </td>
    `;
    tbody.appendChild(tr);

    const detTr = document.createElement('tr');
    detTr.className = 'detalle-row';
    detTr.style.display = 'none';
    detTr.innerHTML = `<td colspan="7"><div class="row">
      <div class="col-md-6">
        <h5 class="text-white">Resumen por insumo</h5>
        <div class="table-responsive"><table class="styled-table"><thead><tr><th>Insumo</th><th>Unidad</th><th>Cantidad</th></tr></thead><tbody class="tb-resumen"></tbody></table></div>
        <h5 class="text-white mt-3">Devoluciones</h5>
        <div class="table-responsive"><table class="styled-table"><thead><tr><th>Insumo</th><th>Unidad</th><th>Devuelto</th></tr></thead><tbody class="tb-devs"></tbody></table></div>
      </div>
      <div class="col-md-6"><h5 class="text-white">Lotes de salida</h5>
        <div class="table-responsive"><table class="styled-table"><thead><tr><th>Insumo</th><th>Lote(ID)</th><th>Fecha</th><th>Cantidad</th><th>V.Unit</th></tr></thead><tbody class="tb-lotes"></tbody></table></div>
      </div>
    </div></td>`;
    tbody.appendChild(detTr);
  });

  tbody.querySelectorAll('button[data-act="ver"]').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const token = e.currentTarget.getAttribute('data-token');
      const row = e.currentTarget.closest('tr');
      const detRow = row.nextElementSibling;
      if(detRow.style.display==='none'){
        await cargarDetalle(token, detRow);
        detRow.style.display='table-row';
      } else {
        detRow.style.display='none';
      }
    });
  });

  tbody.querySelectorAll('button[data-act="reimp"]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const token = e.currentTarget.getAttribute('data-token');
      window.open('../../api/bodega/qr_pdf.php?token=' + encodeURIComponent(token), '_blank');
    });
  });

  tbody.querySelectorAll('button[data-act="pdf"]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const token = e.currentTarget.getAttribute('data-token');
      const pdf = e.currentTarget.getAttribute('data-pdf');
      if(pdf){
        window.open('../../' + pdf, '_blank');
      } else {
        window.open('../../api/bodega/qr_pdf.php?token=' + encodeURIComponent(token), '_blank');
      }
    });
  });

  // Nota de entrada (PDF de recepción)
  tbody.querySelectorAll('button[data-act="nota"]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const token = e.currentTarget.getAttribute('data-token');
      let pdfRec = e.currentTarget.getAttribute('data-pdf-rec') || '';
      if (!pdfRec || pdfRec === 'null') {
        // Fallback al nombre por convención
        pdfRec = 'uploads/qrs/recepcion_' + token + '.pdf';
      }
      window.open('../../' + pdfRec, '_blank');
    });
  });
}

function getOrdenReque(){
  return ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros'];
}

async function cargarDetalle(token, detRow){
  const resp = await fetch('../../api/bodega/qr_detalle.php?token=' + encodeURIComponent(token));
  const json = await resp.json();
  if(!json.success){ alert(json.mensaje || 'Error'); return; }
  const { resumen_por_insumo, lotes, devoluciones } = json.resultado;
  const tbR = detRow.querySelector('.tb-resumen');
  const tbL = detRow.querySelector('.tb-lotes');
  const tbD = detRow.querySelector('.tb-devs');
  tbR.innerHTML=''; tbL.innerHTML=''; if (tbD) tbD.innerHTML='';

  // Agrupar resumen por reque y pintar cabeceras
  const orden = getOrdenReque();
  const grupos = {};
  (resumen_por_insumo||[]).forEach(r=>{
    const cat = (r.reque || '');
    if(!grupos[cat]) grupos[cat] = [];
    grupos[cat].push(r);
  });
  orden.forEach(cat=>{
    const items = grupos[cat] || [];
    if(!items.length) return;
    const th = document.createElement('tr');
    th.innerHTML = `<td colspan="3" style="font-weight:bold; background:#222; color:#fff; text-align:center;">${cat}</td>`;
    tbR.appendChild(th);
    items.sort((a,b)=> String(a.nombre||'').localeCompare(String(b.nombre||''), undefined, { sensitivity: 'base' }));
    items.forEach(r=>{
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${r.nombre}</td><td>${r.unidad||''}</td><td class="text-end">${Number(r.cantidad_total).toFixed(2)}</td>`;
      tbR.appendChild(tr);
    });
  });

  // Lotes de salida: sin agrupar
  (lotes||[]).forEach(l=>{
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${l.nombre}</td><td>${l.id_entrada||''}</td><td>${l.fecha_entrada||''}</td><td class="text-end">${Number(l.cantidad).toFixed(2)}</td><td class="text-end">${(l.valor_unitario!=null)?Number(l.valor_unitario).toFixed(4):''}</td>`;
    tbL.appendChild(tr);
  });
  if (tbD) {
    (devoluciones||[]).forEach(d=>{
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${d.nombre}</td><td>${d.unidad||''}</td><td class="text-end">${Number(d.cantidad_total).toFixed(2)}</td>`;
      tbD.appendChild(tr);
    });
    if ((devoluciones||[]).length === 0) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td colspan="3">Sin devoluciones</td>`;
      tbD.appendChild(tr);
    }
  }
}

qs('#btnBuscar').addEventListener('click', ()=>{ page=1; cargar(); });
qs('#prevPag').addEventListener('click', ()=>{ if(page>1){page--; cargar();} });
qs('#nextPag').addEventListener('click', ()=>{ const pages = Math.ceil(total/per_page); if(page<pages){page++; cargar();} });

setDefaultDates();
cargar();
</script>
<?php require_once __DIR__ . '/../footer.php'; ?>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
