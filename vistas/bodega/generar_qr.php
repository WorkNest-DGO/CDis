<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$path_actual = str_replace('/CDI', '', $_SERVER['PHP_SELF']);
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}

require_once __DIR__ . '/../../config/db.php';

$res = $conn->query('SELECT id, nombre, unidad, existencia FROM insumos');
$insumos = $res ? $res->fetch_all(MYSQLI_ASSOC) : [];

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
        <div class="table-responsive">
            <table class="styled-table">
                <thead>
                    <tr>
                        <th>Insumo</th>
                        <th>Existencia</th>
                        <th>Unidad</th>
                        <th>Cantidad a enviar</th>
                    </tr>
                </thead>
                <tbody id="tablaInsumos"></tbody>
            </table>
        </div>
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
    body.innerHTML='';
    Object.entries(seleccionados).forEach(([id,val])=>{
        const ins = catalogo.find(x=>x.id == id);
        if(!ins || !ins.nombre || !ins.unidad || val <= 0) return;
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${ins.nombre}</td><td>${val}</td><td>${ins.unidad}</td>`;
        body.appendChild(tr);
    });
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
        const resp = await fetch('../../api/bodega/generar_qr.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ insumos })
        });
        const data = await resp.json();
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
</script>
<?php require_once __DIR__ . '/../footer.php'; ?>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

