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

$res = $conn->query("SELECT id, nombre, unidad, existencia, reque FROM insumos ORDER BY reque, nombre");
$insumos = $res ? $res->fetch_all(MYSQLI_ASSOC) : [];

// Cargar opciones de URL base para QR desde la tabla direccion_qr
$resDir = $conn->query('SELECT ip, nombre FROM direccion_qr');
$direcciones_qr = $resDir ? $resDir->fetch_all(MYSQLI_ASSOC) : [];

$title = 'Generar QR';
ob_start();
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
                <a href="">Catálogo de almacen CDIs</a>
            </div>
        </div>
    </div>
</div>
<div class="container mt-4">
    <h2 class="text-white">Generar QR para salida de insumos</h2>
    <div id="resultado" class="mb-3"></div>
    <div id="resultado2" class="mb-3"></div>
    <form id="formQR">
        <div class="row mb-2">
            <div class="col-md-6 mb-2">
                <input type="text" id="buscarInsumo" class="form-control" placeholder="Buscar insumo">
            </div>
            <div class="col-md-2">
                <select id="itemsPagina" class="form-select">
                    <option value="15">15</option>
                    <option value="25">25</option>
                    <option value="50">50</option>
                </select>
            </div>
        </div>
        <div class="row mb-3">
            <div class="col-md-6">
                <label for="urlBase" class="text-white me-2">URL base QR</label>
                <select id="urlBase" class="form-select">
                    <option value="">(Usar default https://tokyosushiprime.com)</option>
<?php foreach ($direcciones_qr as $d): ?>
                    <option value="<?= htmlspecialchars($d['ip']) ?>"><?= htmlspecialchars(($d['nombre'] ?: '') . (isset($d['ip']) && $d['ip'] ? ' — ' . $d['ip'] : '')) ?></option>
<?php endforeach; ?>
                </select>
            </div>
        </div>
        <div id="seccionesInsumos"></div>
        <div class="d-flex justify-content-center my-2">
            <button type="button" id="prevPag" class="btn custom-btn me-2">Anterior</button>
            <button type="button" id="nextPag" class="btn custom-btn">Siguiente</button>
        </div>
        <h5 class="text-white">Resumen</h5>
        <div class="table-responsive">
            <table class="styled-table" id="tablaResumen">
                <thead>
                    <tr><th>Insumo</th><th>Cantidad</th><th>Unidad</th></tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
        <div class="mt-3 print-controls">
            <label class="text-white me-2">Impresora</label>
            <select class="sel-impresora"><option value="">(Selecciona impresora)</option></select>
        </div>
        <button type="button" id="btnGenerar" class="btn custom-btn mt-3">Generar QR</button>
    </form>
</div>
<script>
const catalogo = <?= json_encode($insumos) ?>;
let filtrado = catalogo;
let items = 15;
let pagina = 1;
let seleccionados = JSON.parse(localStorage.getItem('qr_actual') || '{}');

function renderTabla(){
    const tbody = document.getElementById('tablaInsumos');
    tbody.innerHTML = '';
    const inicio = (pagina-1)*items;
    const fin = inicio + items;
    filtrado.slice(inicio,fin).forEach(i => {
        const tr = document.createElement('tr');
        const val = seleccionados[i.id] || '';
        tr.innerHTML = `<td>${i.nombre}</td><td>${i.existencia}</td><td>${i.unidad}</td><td><input type="number" step="0.01" min="0" data-id="${i.id}" class="form-control" value="${val}"></td>`;
        tbody.appendChild(tr);
    });
    tbody.querySelectorAll('input').forEach(inp=>{
        inp.addEventListener('input', onInputChange);
    });
}

function onInputChange(e){
    const id = e.target.dataset.id;
    const val = parseFloat(e.target.value);
    if(!isNaN(val) && val > 0){
        seleccionados[id] = val;
    } else {
        delete seleccionados[id];
    }
    actualizarResumen();
}

function actualizarResumen(){
    const body = document.querySelector('#tablaResumen tbody');
    if (!body) return;
    body.innerHTML='';
    // Agrupar por reque
    const orden = getOrdenReque();
    const grupos = {};
    Object.entries(seleccionados).forEach(([id,val])=>{
        const ins = catalogo.find(x=>String(x.id) === String(id));
        if(!ins || !ins.nombre || !ins.unidad) return;
        const cantidad = parseFloat(val);
        if (isNaN(cantidad) || cantidad <= 0) return;
        const cat = ins.reque || '';
        if (!grupos[cat]) grupos[cat] = [];
        grupos[cat].push({ nombre: ins.nombre, unidad: ins.unidad, cantidad });
    });
    // Pintar por orden predefinido
    orden.forEach(cat => {
        const items = grupos[cat] || [];
        if (!items.length) return;
        const th = document.createElement('tr');
        th.innerHTML = `<td colspan="3" style="font-weight:bold; background:#222; color:#fff; text-align:center;">${cat}</td>`;
        body.appendChild(th);
        // Ordenar por nombre para consistencia
        items.sort((a,b)=> a.nombre.localeCompare(b.nombre, undefined, { sensitivity:'base' }));
        items.forEach(r => {
            const tr = document.createElement('tr');
            tr.innerHTML = `<td>${r.nombre}</td><td>${r.cantidad}</td><td>${r.unidad}</td>`;
            body.appendChild(tr);
        });
    });
    // Guardar selección
    localStorage.setItem('qr_actual', JSON.stringify(seleccionados));
}

function filtrar(){
    const t = document.getElementById('buscarInsumo').value.toLowerCase();
    filtrado = catalogo.filter(i=>i.nombre.toLowerCase().includes(t));
    pagina=1;
    renderTabla();
    actualizarResumen();
}

document.getElementById('buscarInsumo').addEventListener('keyup',filtrar);
document.getElementById('itemsPagina').addEventListener('change', e=>{
    items = parseInt(e.target.value);
    pagina=1;
    renderTabla();
    actualizarResumen();
});
document.getElementById('prevPag').addEventListener('click',()=>{
    if(pagina>1){pagina--;renderTabla();actualizarResumen();}
});
document.getElementById('nextPag').addEventListener('click',()=>{
    const total = Math.ceil(filtrado.length/items); if(pagina<total){pagina++;renderTabla();actualizarResumen();}
});

renderTabla();
actualizarResumen();

document.getElementById('btnGenerar').addEventListener('click', async function(e){
    e.preventDefault();
    const insumos = Object.entries(seleccionados).map(([id,cantidad])=>({id:parseInt(id), cantidad:parseFloat(cantidad)}));
    if(insumos.length === 0){
        alert('Ingresa cantidades válidas');
        return;
    }
    try {
        const urlBaseSel = document.getElementById('urlBase');
        const url_base = urlBaseSel && urlBaseSel.value ? urlBaseSel.value : '';
        const resp = await fetch('../../api/bodega/generar_qr.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ insumos, url_base })
        });
        const text = await resp.text();
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            console.error("Respuesta no es JSON:", text);
            alert("Error al procesar la respuesta del servidor.");
            return;
        }
        if(data.success){
            const url = data.resultado.url;
            const pdf = '../../' + data.resultado.pdf_url;
            const img = '../../' + data.resultado.qr_url;
            document.getElementById('resultado').innerHTML =
                '<p class="text-white">Escanea el código para recibir:</p>'+
                '<img src="'+img+'" alt="QR" width="200" height="200">'+
                '<p class="mt-2"><a class="btn custom-btn" href="'+pdf+'" target="_blank">Ver PDF</a></p>'+
                '<p class="mt-2"><a class="btn custom-btn" href="../../api/bodega/imprimir_qr.php?qrName='+img+'"  target="_blank">Imprimir PDF</a></p>';
            seleccionados = {};
            localStorage.removeItem('qr_actual');
            renderTabla();
            actualizarResumen();
           
        } else {
            alert(data.mensaje || 'Error');
        }
    } catch(err){
        console.error(err);
        alert('Error de comunicación');
    }
});

// Agrupación por categoría (reque) y render por secciones (5 tablas)
function getOrdenReque(){
    // Solo las 5 categorías del enum (sin vacío)
    return ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros'];
}
function renderTabla(){
    const cont = document.getElementById('seccionesInsumos');
    if (!cont) return;
    cont.innerHTML = '';
    const categorias = getOrdenReque();
    categorias.forEach(cat => {
        const itemsCat = (filtrado || []).filter(i => (i.reque || '') === cat);
        if (!itemsCat.length) return;
        const sec = document.createElement('div');
        sec.className = 'mb-4';
        const headerHtml = `<h5 class="text-white mb-2">${cat}</h5>`;
        const thead = `
            <thead>
                <tr>
                    <th>Insumo</th>
                    <th>Existencia</th>
                    <th>Unidad</th>
                    <th>Cantidad a enviar</th>
                </tr>
            </thead>`;
        let rows = '';
        itemsCat.forEach(i => {
            const val = seleccionados[i.id] || '';
            rows += `<tr>
                        <td>${i.nombre}</td>
                        <td>${i.existencia ?? ''}</td>
                        <td>${i.unidad ?? ''}</td>
                        <td><input type="number" step="0.01" min="0" data-id="${i.id}" class="form-control" value="${val}"></td>
                    </tr>`;
        });
        sec.innerHTML = headerHtml +
            `<div class="table-responsive">
                <table class="styled-table">
                    ${thead}
                    <tbody>${rows}</tbody>
                </table>
            </div>`;
        cont.appendChild(sec);
    });
    cont.querySelectorAll('input[data-id]').forEach(inp => inp.addEventListener('input', onInputChange));
}
</script>
<script>
// Llenado de selects de impresoras y hook para el link de impresión
function cargarImpresoras($sel){
 fetch('/rest2/CDI/api/impresoras/listar.php', { cache: 'no-store' })
    .then(r=>r.json()).then(j=>{
      const data = j && (j.resultado || j.data) || [];
      if(!$sel) return;
      $sel.innerHTML = '<option value="">(Selecciona impresora)</option>';
      (data||[]).forEach(p=>{
        const opt = document.createElement('option');
        opt.value = p.ip;
        opt.textContent = ((p.lugar||'') + ' — ' + p.ip).trim();
        $sel.appendChild(opt);
      });
    }).catch(console.error);
}
document.addEventListener('DOMContentLoaded',()=>{
  document.querySelectorAll('.sel-impresora').forEach(cargarImpresoras);
  document.addEventListener('click', function(ev){
    const a = ev.target.closest('a');
    if (!a) return;
    if (a.getAttribute('href') && a.getAttribute('href').includes('/api/bodega/imprimir_qr.php')){
      const sel = document.querySelector('.sel-impresora');
      const v = sel && sel.value ? sel.value : '';
      try {
        const url = new URL(a.href, window.location.origin);
        if (v) url.searchParams.set('printer_ip', v); else url.searchParams.delete('printer_ip');
        a.href = url.pathname + url.search;
      } catch(e) { if (v) { a.href = a.href + (a.href.includes('?') ? '&' : '?') + 'printer_ip=' + encodeURIComponent(v); } }
    }
  });
});
</script>
<?php require_once __DIR__ . '/../footer.php'; ?>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

