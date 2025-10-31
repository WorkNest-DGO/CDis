const usuarioId = 1; // reemplazar con id de sesión en producción
let detalles = [];
let corteActual = null;
let pagina = 1;
let pageSize = 15;
// Estado para Reporte Entradas/Salidas
let reporteRows = [];
let reportePage = 1;
let reportePageSize = 25;

async function abrirCorte() {
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'abrir', usuario_id: usuarioId })
        });
        const data = await resp.json();
        if (data.success) {
            alert('Corte abierto ID: ' + data.resultado.corte_id);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al abrir corte');
    }
}

function cerrarCorte() {
    document.getElementById('formObservaciones').style.display = 'block';
}

async function guardarCierre() {
    const obs = document.getElementById('observaciones').value;
    const btn = document.getElementById('guardarCierre');
    if (btn) btn.disabled = true;
    try {
        // Obtener el corte abierto desde la API (regla: solo puede haber uno)
        const listarResp = await fetch('../../api/insumos/cortes_almacen.php?accion=listar');
        const listarData = await listarResp.json();
        let corteId = null;
        if (listarData && listarData.success && Array.isArray(listarData.resultado)) {
            const abierto = listarData.resultado.find(c => c && (c.fecha_fin === null || String(c.fecha_fin).trim() === ''));
            if (abierto) corteId = abierto.id;
        }
        if (!corteId) {
            alert('No hay un corte abierto para cerrar.');
            return;
        }

        // Cerrar el corte encontrado automáticamente
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'cerrar', corte_id: corteId, usuario_id: usuarioId, observaciones: obs })
        });
        const data = await resp.json();
        if (data.success) {
            corteActual = corteId;
            detalles = data.resultado.detalles;
            pagina = 1;
            renderTabla();
            document.getElementById('formObservaciones').style.display = 'none';
            // limpiar observaciones
            try { document.getElementById('observaciones').value = ''; } catch(e) {}
            // actualizar estado del botón Abrir (ya no debe haber abierto)
            try { validarBotonAbrirCorte(); } catch(e) {}
        } else {
            alert(data.mensaje || 'No se pudo cerrar el corte');
        }
    } catch (err) {
        console.error(err);
        alert('Error al cerrar');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function buscarCortes() {
    const fecha = document.getElementById('buscarFecha').value;
    const lista = document.getElementById('listaCortes');
    lista.innerHTML = '<option value="">Buscando...</option>';
    try {
        const resp = await fetch(`../../api/insumos/cortes_almacen.php?accion=listar&fecha=${fecha}`);
        const data = await resp.json();
        lista.innerHTML = '<option value="">Seleccione corte...</option>';
        if (data.success) {
            data.resultado.forEach(c => {
                const hora = c.fecha_inicio.split(' ')[1];
                const opt = document.createElement('option');
                opt.value = c.id;
                opt.textContent = `${c.id} - ${hora} - ${c.abierto_por}`;
                lista.appendChild(opt);
            });
        }
    } catch (err) {
        console.error(err);
        lista.innerHTML = '<option value="">Error</option>';
    }
}

async function cargarDetalle(id) {
    if (!id) return;
    try {
        // Cálculo en tiempo real por corte (sin requerir cierre)
        const resp = await fetch(`../../api/insumos/listar_cortes_almacen_detalle.php?corte_id=${encodeURIComponent(id)}`);
        const data = await resp.json();
        if (data && data.success) {
            corteActual = id;
            const rows = Array.isArray(data.resultado) ? data.resultado : (data.items || []);
            detalles = Array.isArray(rows) ? rows : [];
            pagina = 1;
            renderTabla();
        } else if (Array.isArray(data)) {
            corteActual = id;
            detalles = data;
            pagina = 1;
            renderTabla();
        }
    } catch (err) {
        console.error(err);
    }
}

function actualizarTablaCorte(){
    const sel = document.getElementById('listaCortes');
    const id = sel && sel.value ? sel.value : (corteActual || '');
    if (!id) { alert('Seleccione un corte'); return; }
    cargarDetalle(id);
}

function renderTabla() {
    const filtro = document.getElementById('filtroInsumo').value.toLowerCase();
    const tbody = document.querySelector('#tablaResumen tbody');
    tbody.innerHTML = '';
    pageSize = parseInt(document.getElementById('registrosPagina').value, 10);
    const filtrados = detalles.filter(d => String(d.insumo||'').toLowerCase().includes(filtro));
    const inicio = (pagina - 1) * pageSize;
    const paginados = filtrados.slice(inicio, inicio + pageSize);
    paginados.forEach(d => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${d.insumo}</td><td>${d.existencia_inicial}</td><td>${d.entradas}</td><td>${d.salidas}</td><td>${d.mermas}</td><td>${d.existencia_final}</td>`;
        tbody.appendChild(tr);
    });
    // Total de mermas mostradas (paginado actual)
    try{
      const tot = paginados.reduce((acc, it)=> acc + (parseFloat(it.mermas)||0), 0);
      const box = document.getElementById('totMermas');
      if (box) box.textContent = 'Total mermas (página actual): ' + (Number.isFinite(tot)? tot.toFixed(2): '0.00');
    }catch(e){}
}

async function exportarExcel() {
    if (!corteActual) {
        alert('Seleccione un corte');
        return;
    }
    try {
        const resp = await fetch(`../../api/insumos/cortes_almacen.php?action=exportarExcel&id=${corteActual}`);
        const data = await resp.json();
        if (data.success) {
            window.open(data.resultado.archivo, '_blank');
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('No se pudo exportar');
    }
}

async function exportarPdf() {
    if (!corteActual) {
        alert('Seleccione un corte');
        return;
    }
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'exportar_pdf', corte_id: corteActual })
        });
        const data = await resp.json();
        if (data.success) {
            window.open(data.resultado.archivo, '_blank');
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('No se pudo exportar');
    }
}

function cambiarPagina(delta) {
    const total = detalles.filter(d => d.insumo.toLowerCase().includes(document.getElementById('filtroInsumo').value.toLowerCase())).length;
    const maxPagina = Math.ceil(total / pageSize);
    pagina += delta;
    if (pagina < 1) pagina = 1;
    if (pagina > maxPagina) pagina = maxPagina;
    renderTabla();
}

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('btnAbrirCorte')?.addEventListener('click', abrirCorte);
    document.getElementById('btnCerrarCorte')?.addEventListener('click', cerrarCorte);
    document.getElementById('guardarCierre')?.addEventListener('click', guardarCierre);
    document.getElementById('btnBuscar')?.addEventListener('click', buscarCortes);
    document.getElementById('listaCortes')?.addEventListener('change', e => cargarDetalle(e.target.value));
    document.getElementById('filtroInsumo')?.addEventListener('input', () => { pagina = 1; renderTabla(); });
    document.getElementById('registrosPagina')?.addEventListener('change', () => { pagina = 1; renderTabla(); });
    document.getElementById('btnActualizarCorte')?.addEventListener('click', actualizarTablaCorte);
    document.getElementById('btnExportarExcel')?.addEventListener('click', exportarExcel);
    document.getElementById('btnExportarPdf')?.addEventListener('click', exportarPdf);
    document.getElementById('prevPagina')?.addEventListener('click', () => cambiarPagina(-1));
    document.getElementById('nextPagina')?.addEventListener('click', () => cambiarPagina(1));

    // Reporte: filtros y eventos
    document.getElementById('modoReporte')?.addEventListener('change', onChangeModoReporte);
    document.getElementById('btnGenerarReporte')?.addEventListener('click', fetchReporteEntradasSalidas);
    document.getElementById('btnExportCsv')?.addEventListener('click', () => exportarReporte('csv'));
    document.getElementById('btnExportPdf')?.addEventListener('click', () => exportarReporte('pdf'));
    document.getElementById('modalDetalleCerrar')?.addEventListener('click', cerrarModalDetalle);

    // Inicializar modo y cortes
    try { onChangeModoReporte(); } catch (e) {}
    try { cargarListaCortesParaReporte(); } catch (e) {}

    // Inicializar fecha al día actual si está vacía
    try {
        const df = document.getElementById('buscarFecha');
        if (df && !df.value) {
            const d = new Date();
            const yyyy = d.getFullYear();
            const mm = String(d.getMonth()+1).padStart(2,'0');
            const dd = String(d.getDate()).padStart(2,'0');
            df.value = `${yyyy}-${mm}-${dd}`;
        }
    } catch(e) {}

    // Validar corte abierto global para habilitar/deshabilitar botón Abrir
    validarBotonAbrirCorte();
});

async function validarBotonAbrirCorte(){
    const btn = document.getElementById('btnAbrirCorte');
    if (!btn) return;
    try{
        const resp = await fetch('../../api/insumos/cortes_almacen.php?accion=listar');
        const data = await resp.json();
        let hayAbierto = false;
        if (data && data.success && Array.isArray(data.resultado)){
            hayAbierto = data.resultado.some(c => c && (c.fecha_fin === null || String(c.fecha_fin).trim() === ''));
        }
        btn.disabled = !!hayAbierto;
    }catch(e){ /* si falla, no bloquear */ }
}

// ==========================
// Reporte Entradas/Salidas
// ==========================

function onChangeModoReporte() {
    const modo = document.getElementById('modoReporte')?.value || 'range';
    const grpDesde = document.getElementById('grpDesde');
    const grpHasta = document.getElementById('grpHasta');
    const grpCorte = document.getElementById('grpCorte');
    if (!grpDesde || !grpHasta || !grpCorte) return;
    if (modo === 'range') {
        grpDesde.style.display = '';
        grpHasta.style.display = '';
        grpCorte.style.display = 'none';
    } else {
        grpDesde.style.display = 'none';
        grpHasta.style.display = 'none';
        grpCorte.style.display = '';
        cargarListaCortesParaReporte();
    }
}

async function cargarListaCortesParaReporte() {
    const sel = document.getElementById('selCorte');
    if (!sel) return;
    sel.innerHTML = '<option value="">Cargando cortes...</option>';
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php?accion=listar');
        const data = await resp.json();
        sel.innerHTML = '<option value="">Seleccione corte...</option>';
        if (data && data.success && Array.isArray(data.resultado)) {
            data.resultado.forEach(c => {
                const fi = c.fecha_inicio ? c.fecha_inicio : '';
                const ff = c.fecha_fin ? c.fecha_fin : '';
                const label = `${c.id} - ${fi?.substring(0,16)} / ${ff ? ff.substring(0,16) : 'abierto'}`;
                const opt = document.createElement('option');
                opt.value = c.id;
                opt.textContent = label;
                sel.appendChild(opt);
            });
        }
    } catch (err) {
        console.error(err);
        sel.innerHTML = '<option value="">Error al cargar</option>'; 
    }
}

function getReporteQueryParams() {
    const modo = document.getElementById('modoReporte')?.value || 'range';
    const devolucionesEnEntradas = document.getElementById('chkDevoEnEntradas')?.checked ? 1 : 0;
    const params = new URLSearchParams();
    params.set('mode', modo);
    params.set('devoluciones_en_entradas', String(devolucionesEnEntradas));
    if (modo === 'range') {
        const df = document.getElementById('dateFrom')?.value;
        const dt = document.getElementById('dateTo')?.value;
        if (df) params.set('date_from', df);
        if (dt) params.set('date_to', dt);
    } else {
        const corteId = document.getElementById('selCorte')?.value;
        if (corteId) params.set('corte_id', corteId);
    }
    return params;
}

async function fetchReporteEntradasSalidas() {
    const estado = document.getElementById('estadoReporte');
    const tbody = document.querySelector('#tablaEntradasSalidas tbody');
    if (estado) { estado.style.display = ''; estado.textContent = 'Cargando...'; }
    if (tbody) { tbody.innerHTML = ''; }
    try {
        const params = getReporteQueryParams();
        // Validación mínima
        const modo = params.get('mode');
        if (modo === 'range' && (!params.get('date_from') || !params.get('date_to'))) {
            if (estado) { estado.textContent = 'Seleccione fechas válidas'; }
            return;
        }
        if (modo === 'corte' && !params.get('corte_id')) {
            if (estado) { estado.textContent = 'Seleccione un corte'; }
            return;
        }
        const url = new URL('../../api/reportes/entradas-salidas.php', document.baseURI);
        url.search = params.toString();
        const resp = await fetch(url.toString(), { headers: { 'Accept': 'application/json' } });
        if (!resp.ok) { throw new Error('HTTP ' + resp.status); }
        const data = await resp.json();
        // Guardar filas para paginado/búsqueda en cliente
        reporteRows = Array.isArray(data.rows) ? data.rows : [];
        reportePage = 1;
        const psSel = document.getElementById('reportePageSize');
        if (psSel) { const v = parseInt(psSel.value||'25',10); if (v>0) reportePageSize = v; }
        renderReporte(data); // para totales
        renderReportePaginado();
        if (estado) { estado.textContent = (Array.isArray(data.rows) && data.rows.length > 0) ? 'Listo' : 'Sin datos para el periodo.'; }
    } catch (err) {
        console.error(err);
        if (estado) { estado.textContent = 'Error al cargar: ' + (err?.message || err); }
    }
}

function renderReporte(data) {
    const tbody = document.querySelector('#tablaEntradasSalidas tbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    // El render de filas lo hace renderReportePaginado; aquí solo limpiar tbody para evitar parpadeos con totales
    tbody.innerHTML = '';
    // Totales
    const t = data.totales || {};
    setText('totInicial', t.inicial);
    setText('totEntradas', t.entradas_compra);
    setText('totDevoluciones', t.devoluciones);
    setText('totOtras', t.otras_entradas);
    setText('totSalidas', t.salidas);
    setText('totTrasp', t.traspasos_salida);
    setText('totMermas', t.mermas);
    setText('totAjustesNeg', t.ajustes_neg);
    setText('totAjustesPos', t.ajustes_pos);
    setText('totFinal', t.final);

    // El bind de click se hará en renderReportePaginado()
}

function renderReportePaginado(){
    const tbody = document.querySelector('#tablaEntradasSalidas tbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    const filtro = (document.getElementById('reporteFiltroInsumo')?.value || '').toLowerCase();
    const base = Array.isArray(reporteRows) ? reporteRows : [];
    const filtrados = filtro ? base.filter(r => String(r.insumo||'').toLowerCase().includes(filtro)) : base;
    // Enriquecer con grupo derivado de reque_id (preferir datos del backend; fallback a preload de listar_insumos)
    const rowsConGrupo = filtrados.map(r => {
        let gid = Number(r.reque_id || 0);
        let gname = '';
        if (gid > 0) {
            gname = r.reque_nombre || String(gid);
        } else {
            const info = (window.__requeByInsumo && window.__requeByInsumo[r.insumo_id]) ? window.__requeByInsumo[r.insumo_id] : { id: 0, nombre: '' };
            gid = Number(info && info.id ? info.id : 0);
            gname = gid > 0 ? String(info.nombre || gid) : 'N/A';
        }
        return Object.assign({}, r, { grupoId: gid, grupoNombre: gname });
    }).sort((a,b)=>{
        const gcmp = (a.grupoId||0) - (b.grupoId||0);
        if (gcmp !== 0) return gcmp;
        return String(a.insumo||'').localeCompare(String(b.insumo||''), undefined, { sensitivity:'base' });
    });
    const total = rowsConGrupo.length;
    const totalPages = Math.max(1, Math.ceil(total / Math.max(1, reportePageSize)));
    if (reportePage > totalPages) reportePage = totalPages;
    const start = (reportePage - 1) * reportePageSize;
    const pageRows = rowsConGrupo.slice(start, start + reportePageSize);
    let lastGroup = null;
    pageRows.forEach(r => {
        const areaText = (r.grupoId && r.grupoId > 0) ? `${r.grupoId} - ${r.grupoNombre || r.grupoId}` : 'N/A';
        if (r.grupoId !== lastGroup) {
            const th = document.createElement('tr');
            // colspan: 13 columnas (Área + 12 métricas)
            th.innerHTML = `<td colspan="13" style="font-weight:bold; background:#222; color:#fff; text-align:center;">${areaText}</td>`;
            tbody.appendChild(th);
            lastGroup = r.grupoId;
        }
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>${areaText}</td>
            <td class="link-insumo" data-insumo-id="${r.insumo_id}" style="cursor:pointer; text-decoration:underline;">${r.insumo}</td>
            <td>${r.unidad ?? ''}</td>
            <td>${fmt(r.inicial)}</td>
            <td>${fmt(r.entradas_compra)}</td>
            <td>${fmt(r.devoluciones)}</td>
            <td>${fmt(r.otras_entradas)}</td>
            <td>${fmt(r.salidas)}</td>
            <td>${fmt(r.traspasos_salida)}</td>
            <td>${fmt(r.mermas)}</td>
            <td>${fmt(r.ajustes_neg)}</td>
            <td>${fmt(r.ajustes_pos)}</td>
            <td>${fmt(r.final)}</td>
        `;
        tbody.appendChild(tr);
    });
    // bind detalle
    tbody.querySelectorAll('.link-insumo').forEach(el => {
        el.addEventListener('click', (ev) => {
            const id = ev.currentTarget.getAttribute('data-insumo-id');
            if (id) abrirModalDetalle(parseInt(id, 10));
        });
    });
    const info = document.getElementById('reportePageInfo');
    if (info) info.textContent = `Página ${total === 0 ? 0 : reportePage}/${totalPages}`;
}

function setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = fmt(val);
}

function fmt(v) {
    const n = Number(v ?? 0);
    return n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function buildReporteUrlWithFormat(format) {
    const params = getReporteQueryParams();
    params.set('format', format);
    const url = new URL('../../api/reportes/entradas-salidas.php', document.baseURI);
    url.search = params.toString();
    return url.toString();
}

function exportarReporte(fmt) {
    const estado = document.getElementById('estadoReporte');
    try {
        const modo = document.getElementById('modoReporte')?.value || 'range';
        if (modo === 'range' && (!document.getElementById('dateFrom')?.value || !document.getElementById('dateTo')?.value)) {
            if (estado) estado.textContent = 'Seleccione fechas válidas';
            return;
        }
        if (modo === 'corte' && !document.getElementById('selCorte')?.value) {
            if (estado) estado.textContent = 'Seleccione un corte';
            return;
        }
        const url = buildReporteUrlWithFormat(fmt);
        window.open(url, '_blank');
    } catch (err) {
        console.error(err);
        if (estado) estado.textContent = 'No se pudo exportar';
    }
}

// Listeners de UI para reporte (paginación/búsqueda)
// Registrar listeners inmediatamente (el script se incluye al final del body)
try {
    const inp = document.getElementById('reporteFiltroInsumo');
    if (inp) inp.addEventListener('input', () => { reportePage = 1; renderReportePaginado(); });
    const sel = document.getElementById('reportePageSize');
    if (sel) sel.addEventListener('change', () => { reportePageSize = parseInt(sel.value||'25',10)||25; reportePage = 1; renderReportePaginado(); });
    const prev = document.getElementById('reportePrev');
    if (prev) prev.addEventListener('click', () => { if (reportePage > 1) { reportePage--; renderReportePaginado(); } });
    const next = document.getElementById('reporteNext');
    if (next) next.addEventListener('click', () => {
        const filtro = (document.getElementById('reporteFiltroInsumo')?.value || '').toLowerCase();
        const base = Array.isArray(reporteRows) ? reporteRows : [];
        const total = (filtro ? base.filter(r => String(r.insumo||'').toLowerCase().includes(filtro)) : base).length;
        const totalPages = Math.max(1, Math.ceil(total / Math.max(1, reportePageSize)));
        if (reportePage < totalPages) { reportePage++; renderReportePaginado(); }
    });
} catch(e) {}

// Precargar mapa de reque (grupo) por insumo usando listar_insumos
(async function preloadReque(){
  try {
    const resp = await fetch('../../api/insumos/listar_insumos.php', { cache: 'no-store' });
    const data = await resp.json();
    if (data && data.success) {
      const mapa = {};
      const arr = Array.isArray(data.resultado) ? data.resultado : (data || []);
      arr.forEach(i => {
        if (i && typeof i.id !== 'undefined') {
          const rid = Number(i.reque_id || 0);
          const rname = rid > 0 ? (i.reque_nombre || '') : 'N/A';
          mapa[Number(i.id)] = { id: rid, nombre: rname };
        }
      });
      window.__requeByInsumo = mapa;
    }
  } catch(e) { window.__requeByInsumo = window.__requeByInsumo || {}; }
})();

async function abrirModalDetalle(insumoId) {
    const modal = document.getElementById('modalDetalle');
    const tbody = document.querySelector('#tablaDetalleLotes tbody');
    if (!modal || !tbody) return;
    tbody.innerHTML = '<tr><td colspan="9">Cargando...</td></tr>';
    modal.style.display = '';
    try {
        const params = getReporteQueryParams();
        params.set('insumo_id', String(insumoId));
        const url = new URL('../../api/reportes/entradas-salidas_detalle.php', document.baseURI);
        url.search = params.toString();
        const resp = await fetch(url.toString(), { headers: { 'Accept': 'application/json' } });
        const data = await resp.json();
        renderDetalle(data);
    } catch (err) {
        console.error(err);
        tbody.innerHTML = '<tr><td colspan="9">Error al cargar</td></tr>';
    }
}

function renderDetalle(data) {
    const tbody = document.querySelector('#tablaDetalleLotes tbody');
    if (!tbody) return;
    const lotes = Array.isArray(data.lotes) ? data.lotes : [];
    if (lotes.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9">Sin movimientos</td></tr>';
        return;
    }
    tbody.innerHTML = '';
    lotes.forEach(l => {
        const tr = document.createElement('tr');
        const qrs = Array.isArray(l.qrs) ? l.qrs.join(', ') : '';
        tr.innerHTML = `
            <td>${l.fecha ?? ''}</td>
            <td>${l.id_entrada}</td>
            <td>${fmt(l.saldo_inicial)}</td>
            <td>${fmt(l.entradas)}</td>
            <td>${fmt(l.salidas)}</td>
            <td>${fmt(l.mermas)}</td>
            <td>${fmt(l.ajustes)}</td>
            <td>${fmt(l.saldo_final)}</td>
            <td>${qrs}</td>
        `;
        tbody.appendChild(tr);
    });
}

function cerrarModalDetalle() {
    const modal = document.getElementById('modalDetalle');
    if (modal) modal.style.display = 'none';
}
