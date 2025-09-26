function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;
const usuarioId = 1; // En producción usar id de sesión
const apiReportes = '../../api/reportes/vistas_db.php';

async function cargarUsuarios() {
    const sel = document.getElementById('filtroUsuario');
    if (!sel) return;
    const r = await fetch('../../api/usuarios/listar_usuarios.php');
    const d = await r.json();
    sel.innerHTML = '<option value="">--Todos--</option>';
    if (d && (d.success || Array.isArray(d.usuarios))) {
        const arr = Array.isArray(d.resultado) ? d.resultado : (Array.isArray(d.usuarios) ? d.usuarios : []);
        arr.forEach(u => {
            const opt = document.createElement('option');
            opt.value = u.id;
            opt.textContent = u.nombre;
            sel.appendChild(opt);
        });
    }
}

async function cargarHistorial() {
    const tbody = document.querySelector('#tablaCortes tbody');
    tbody.innerHTML = '<tr><td colspan="11">Cargando...</td></tr>';
    try {
        const params = new URLSearchParams();
        const u = document.getElementById('filtroUsuario').value;
        const i = document.getElementById('filtroInicio').value;
        const f = document.getElementById('filtroFin').value;
        if (u) params.append('usuario_id', u);
        if (i) params.append('inicio', i);
        if (f) params.append('fin', f);
        const resp = await fetch('../../api/corte_caja/listar_cortes.php?' + params.toString());
        const data = await resp.json();
        if (data.success) {
            tbody.innerHTML = '';
            const lista = Array.isArray(data.resultado)
                ? data.resultado
                : (Array.isArray(data.resultado?.cortes) ? data.resultado.cortes : []);
            lista.forEach(c => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${c.id}</td>
                    <td>${c.usuario}</td>
                    <td>${c.fecha_inicio}</td>
                    <td>${c.fecha_fin || ''}</td>
                    <td>${c.total !== null ? c.total : ''}</td>
                    <td>${c.efectivo || ''}</td>
                    <td>${c.boucher || ''}</td>
                    <td>${c.cheque || ''}</td>
                    <td>${c.fondo_inicial || ''}</td>
                    <td>${c.observaciones || ''}</td>
                    <td><button class="btn custom-btn detalle" data-id="${c.id}">Ver detalle</button></td>
                `;
                tbody.appendChild(tr);
            });
            tbody.querySelectorAll('button.detalle').forEach(btn => {
                btn.addEventListener('click', () => verDetalle(btn.dataset.id));
            });
        } else {
            tbody.innerHTML = '<tr><td colspan="7">Error al cargar</td></tr>';
        }
    } catch (err) {
        console.error(err);
        tbody.innerHTML = '<tr><td colspan="7">Error</td></tr>';
    }
}

async function verDetalle(corteId) {
    const modal = document.getElementById('modal');
    modal.innerHTML = 'Cargando...';
    modal.style.display = 'block';
    try {
        const resp = await fetch('../../api/corte_caja/detalle_venta.php?corte_id=' + corteId);
        const data = await resp.json();
        if (data.success) {
            const grupos = {};
            data.detalles.forEach(d => {
                if (!grupos[d.tipo_pago]) grupos[d.tipo_pago] = [];
                grupos[d.tipo_pago].push(d);
            });
            let html = `<h3>Desglose del corte ${corteId}</h3>`;
            ['efectivo', 'boucher', 'cheque'].forEach(tp => {
                const arr = grupos[tp] || [];
                if (!arr.length) return;
                let total = 0;
                html += `<h4>${tp}</h4><table border="1"><thead><tr><th>Descripción</th><th>Cantidad</th><th>Valor</th><th>Subtotal</th></tr></thead><tbody>`;
                arr.forEach(r => {
                    total += r.subtotal;
                    html += `<tr><td>${r.descripcion}</td><td>${r.cantidad}</td><td>${r.valor}</td><td>${r.subtotal}</td></tr>`;
                });
                html += `<tr><td colspan="3"><strong>Total</strong></td><td><strong>${total.toFixed(2)}</strong></td></tr>`;
                html += '</tbody></table>';
            });
            html += '<button class="btn custom-btn" id="cerrarModal">Cerrar</button>';
            modal.innerHTML = html;
            document.getElementById('cerrarModal').addEventListener('click', () => {
                modal.style.display = 'none';
            });
        } else {
            modal.innerHTML = data.mensaje;
        }
    } catch (err) {
        console.error(err);
        modal.innerHTML = 'Error al obtener detalle';
    }
}

async function resumenActual() {
    const modal = document.getElementById('modal');
    modal.innerHTML = 'Cargando...';
    modal.style.display = 'block';
    try {
        const resp = await fetch('../../api/corte_caja/resumen_corte_actual.php?usuario_id=' + usuarioId);
        const data = await resp.json();
        if (!data.success || !data.resultado.abierto) {
            modal.style.display = 'none';
            alert('No hay corte abierto');
            return;
        }
        const r = data.resultado;
        let html = `<h3>Resumen del corte ${r.corte_id}</h3>`;
        html += `<p>Ventas totales: $${r.total}</p>`;
        html += `<p>Número de ventas: ${r.num_ventas}</p>`;
        html += `<p>Total en propinas: $${r.propinas}</p>`;
        if (r.metodos_pago && r.metodos_pago.length) {
            html += '<h4>Métodos de pago</h4><ul>';
            r.metodos_pago.forEach(m => {
                html += `<li>${m.metodo}: $${m.total}</li>`;
            });
            html += '</ul>';
        }
        html += '<button class="btn custom-btn" id="cerrarModal">Cerrar</button>';
        modal.innerHTML = html;
        document.getElementById('cerrarModal').addEventListener('click', () => {
            modal.style.display = 'none';
        });
    } catch (err) {
        console.error(err);
        modal.innerHTML = 'Error al obtener resumen';
    }
}

// --- Reportes dinámicos de vistas/tablas ---
let fuenteActual = '';
let pagina = 1;
let tamPagina = 15;
let termino = '';
let ordenCol = '';
let ordenDir = 'asc';
let debounceTimer;

// Helpers de formato/estilo
function isNumericStr(v) { return typeof v === 'string' && /^-?\d+(?:\.\d+)?$/.test(v.trim()); }
function isNumeric(v) { return typeof v === 'number' || isNumericStr(v); }
function toNumber(v) { return typeof v === 'number' ? v : parseFloat(v); }
function isMoneyColumn(colLower) {
    return /(total|monto|precio|importe|subtotal|propina|fondo|saldo)/.test(colLower);
}
function isCountColumn(colLower) {
    return /(cantidad|numero|número|folio|id|existencia)/.test(colLower);
}
function isDateLike(val) {
    if (val == null) return false;
    if (typeof val !== 'string') return false;
    return /^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?$/.test(val);
}
function formatDate(val) {
    // Mantén formato YYYY-MM-DD HH:mm
    if (!val) return '';
    const s = String(val);
    if (s.length >= 16) return s.slice(0,16).replace('T',' ');
    if (s.length >= 10) return s.slice(0,10);
    return s;
}
function formatMoney(n) {
    const num = toNumber(n);
    if (!isFinite(num)) return String(n ?? '');
    return '$' + num.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
function formatNumber(n, dec = 0) {
    const num = toNumber(n);
    if (!isFinite(num)) return String(n ?? '');
    return num.toLocaleString('es-MX', dec > 0 ? { minimumFractionDigits: dec, maximumFractionDigits: dec } : undefined);
}
function formatCellValue(col, raw) {
    const colL = (col || '').toLowerCase();
    if (raw == null) return '';
    if (isDateLike(raw)) return formatDate(raw);
    if (isMoneyColumn(colL) && isNumeric(raw)) return formatMoney(raw);
    if (isCountColumn(colL) && isNumeric(raw)) return formatNumber(raw, 0);
    if (isNumeric(raw)) {
        // Si tiene decimales, muestra 2; si no, entero
        const hasDec = String(raw).includes('.');
        return formatNumber(raw, hasDec ? 2 : 0);
    }
    const s = String(raw);
    if (s.length > 120) return s.slice(0, 117) + '…';
    return s;
}
function alignForCol(col, raw) {
    const colL = (col || '').toLowerCase();
    if (isDateLike(raw)) return 'center';
    if (isMoneyColumn(colL) || (isNumeric(raw) && !/\D/.test(String(raw)))) return 'right';
    if (/^fecha/.test(colL)) return 'center';
    return 'left';
}

async function listarFuentes() {
    const select = document.getElementById('selectFuente');
    if (!select) return;
    try {
        const resp = await fetch(`${apiReportes}?action=list_sources`);
        const data = await resp.json();
        select.innerHTML = '';
        const ogV = document.createElement('optgroup');
        ogV.label = 'Vistas';
        data.views.forEach(v => {
            const o = document.createElement('option');
            o.value = v;
            o.textContent = v;
            ogV.appendChild(o);
        });
        const ogT = document.createElement('optgroup');
        ogT.label = 'Tablas';
        data.tables.forEach(t => {
            const o = document.createElement('option');
            o.value = t;
            o.textContent = t;
            ogT.appendChild(o);
        });
        if (data.views.length) {
            select.appendChild(ogV);
            select.appendChild(ogT);
            select.value = data.views[0];
        } else {
            select.appendChild(ogV);
            select.appendChild(ogT);
            if (data.tables.length) select.value = data.tables[0];
        }
        fuenteActual = select.value;
        cargarFuente();
    } catch (err) {
        console.error(err);
    }
}

async function cargarFuente() {
    const tabla = document.getElementById('tablaReportes');
    if (!tabla) return;
    const thead = tabla.querySelector('thead');
    const tbody = tabla.querySelector('tbody');
    const loader = document.getElementById('reportesLoader');
    loader.style.display = 'block';
    tbody.innerHTML = '';
    const params = new URLSearchParams({
        action: 'fetch',
        source: fuenteActual,
        page: pagina,
        pageSize: tamPagina
    });
    if (termino) params.append('q', termino);
    if (ordenCol) {
        params.append('sortBy', ordenCol);
        params.append('sortDir', ordenDir);
    }
    try {
        const resp = await fetch(`${apiReportes}?${params.toString()}`);
        const data = await resp.json();
        loader.style.display = 'none';
        if (data.error) {
            thead.innerHTML = '';
            tbody.innerHTML = `<tr><td colspan="1">${data.error}</td></tr>`;
            document.getElementById('infoReportes').textContent = '';
            return;
        }
        // Header
        thead.innerHTML = '';
        const trHead = document.createElement('tr');
        data.columns.forEach(c => {
            const th = document.createElement('th');
            th.dataset.col = c;
            th.textContent = c;
            trHead.appendChild(th);
        });
        thead.appendChild(trHead);

        // Body con formato
        if (!data.rows.length) {
            const tr = document.createElement('tr');
            const td = document.createElement('td');
            td.colSpan = data.columns.length;
            td.textContent = 'Sin resultados';
            tr.appendChild(td);
            tbody.appendChild(tr);
        } else {
            const frag = document.createDocumentFragment();
            data.rows.forEach(r => {
                const tr = document.createElement('tr');
                data.columns.forEach(c => {
                    const td = document.createElement('td');
                    const val = r[c];
                    td.textContent = formatCellValue(c, val);
                    const align = alignForCol(c, val);
                    if (align === 'right') td.style.textAlign = 'right';
                    else if (align === 'center') td.style.textAlign = 'center';
                    tr.appendChild(td);
                });
                frag.appendChild(tr);
            });
            tbody.appendChild(frag);
        }
        const inicio = data.total ? ((data.page - 1) * data.pageSize + 1) : 0;
        const fin = Math.min(data.page * data.pageSize, data.total);
        document.getElementById('infoReportes').textContent = `Mostrando ${inicio}-${fin} de ${data.total}`;
        document.getElementById('prevReportes').disabled = data.page <= 1;
        document.getElementById('nextReportes').disabled = data.page * data.pageSize >= data.total;
    } catch (err) {
        loader.style.display = 'none';
        console.error(err);
        tbody.innerHTML = `<tr><td colspan="1">Error al cargar</td></tr>`;
    }
}

function initReportesDinamicos() {
    const select = document.getElementById('selectFuente');
    if (!select) return;
    listarFuentes();
    select.addEventListener('change', () => {
        fuenteActual = select.value;
        pagina = 1;
        cargarFuente();
    });
    const btnExport = document.getElementById('btnExportCSV');
    if (btnExport) {
        btnExport.addEventListener('click', () => {
            if (!fuenteActual) return;
            const params = new URLSearchParams({ action: 'export_csv', source: fuenteActual });
            if (termino) params.append('q', termino);
            if (ordenCol) { params.append('sortBy', ordenCol); params.append('sortDir', ordenDir); }
            const url = `${apiReportes}?${params.toString()}`;
            // Abrir en nueva pestaña para descargar
            window.open(url, '_blank');
        });
    }
    document.getElementById('buscarFuente').addEventListener('input', e => {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
            termino = e.target.value;
            pagina = 1;
            cargarFuente();
        }, 300);
    });
    document.getElementById('tamPagina').addEventListener('change', e => {
        tamPagina = parseInt(e.target.value, 10);
        pagina = 1;
        cargarFuente();
    });
    document.getElementById('prevReportes').addEventListener('click', () => {
        if (pagina > 1) {
            pagina--;
            cargarFuente();
        }
    });
    document.getElementById('nextReportes').addEventListener('click', () => {
        pagina++;
        cargarFuente();
    });
    document.querySelector('#tablaReportes thead').addEventListener('click', e => {
        if (e.target.tagName === 'TH') {
            const col = e.target.dataset.col;
            if (ordenCol === col) {
                ordenDir = ordenDir === 'asc' ? 'desc' : 'asc';
            } else {
                ordenCol = col;
                ordenDir = 'asc';
            }
            cargarFuente();
        }
    });
}

document.addEventListener('DOMContentLoaded', () => {
    cargarUsuarios();
    cargarHistorial();
    document.getElementById('btnResumen').addEventListener('click', resumenActual);
    const btn = document.getElementById('aplicarFiltros');
    if (btn) btn.addEventListener('click', cargarHistorial);
    const imp = document.getElementById('btnImprimir');
    if (imp) imp.addEventListener('click', () => window.print());
    initReportesDinamicos();
});
