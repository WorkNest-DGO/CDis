// Utilidades de modal (reuso del patrón de insumos.js)
function showModal(selector) {
    try { if (window.jQuery && typeof $(selector)?.modal === 'function') { $(selector).modal('show'); return; } } catch (e) {}
    const el = document.querySelector(selector); if (!el) return; el.classList.add('show'); el.style.display = 'block';
    document.body.classList.add('modal-open'); const bd = document.createElement('div'); bd.className = 'modal-backdrop fade show'; document.body.appendChild(bd);
}
function hideModal(selector) {
    try { if (window.jQuery && typeof $(selector)?.modal === 'function') { $(selector).modal('hide'); return; } } catch (e) {}
    const el = document.querySelector(selector); if (!el) return; el.classList.remove('show'); el.style.display = 'none';
    document.body.classList.remove('modal-open'); document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());
}
function showAppMsg(msg) { const body = document.querySelector('#appMsgModal .modal-body'); if (body) body.textContent = String(msg); showModal('#appMsgModal'); }
window.alert = showAppMsg;

const qs = (r, s) => (r || document).querySelector(s);
const qsa = (r, s) => Array.from((r || document).querySelectorAll(s));
const fmt$ = n => { const v = parseFloat(String(n).replace(',', '.')); return Number.isFinite(v) ? v.toFixed(2) : ''; };

async function cargarEntradasPagos() {
    const credito = qs(document, '#filtroCredito')?.value ?? '';
    const pagado = qs(document, '#filtroPagado')?.value ?? '';
    const q = qs(document, '#busqueda')?.value.trim() ?? '';
    const params = new URLSearchParams();
    if (credito !== '') params.set('credito', credito);
    if (pagado !== '') params.set('pagado', pagado);
    if (q) params.set('q', q);
    try {
        const resp = await fetch(`../../api/insumos/listar_entradas_pagos.php?${params.toString()}`);
        const data = await resp.json();
        if (!data.success) { alert(data.mensaje || 'Error al cargar'); return; }
        renderTabla(data.resultado || []);
    } catch (e) {
        console.error(e); alert('Error de comunicación');
    }
}

function renderTabla(rows) {
    const tb = qs(document, '#tablaEntradasPagos tbody'); if (!tb) return; tb.innerHTML = '';
    rows.forEach(r => {
        const tr = document.createElement('tr');
        const tipo = String(r.credito) === '1' ? 'Crédito' : 'Efectivo';
        const pagadoTxt = String(r.pagado) === '1' ? 'Sí' : 'No';
        tr.innerHTML = `
            <td><input type="checkbox" class="row-check" data-id="${r.id}"></td>
            <td>${r.id}</td>
            <td>${r.fecha ?? ''}</td>
            <td>${r.proveedor ?? ''}</td>
            <td>${r.producto ?? ''}</td>
            <td>${r.cantidad ?? ''}</td>
            <td>${r.unidad ?? ''}</td>
            <td>${fmt$(r.costo_total ?? '')}</td>
            <td>${tipo}</td>
            <td>${pagadoTxt}</td>
        `;
        tb.appendChild(tr);
    });
}

function seleccionarTodo(v) {
    qsa(document, '.row-check').forEach(ch => ch.checked = v);
    const all = qs(document, '#checkAll'); if (all) all.checked = v;
}

async function marcarPagados() {
    const ids = qsa(document, '.row-check:checked').map(ch => parseInt(ch.dataset.id, 10)).filter(n => Number.isFinite(n) && n > 0);
    if (!ids.length) { alert('Selecciona al menos un registro'); return; }
    try {
        const resp = await fetch('../../api/insumos/marcar_pagados.php', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ids, pagado: 1 })
        });
        const data = await resp.json();
        if (!data.success) { alert(data.mensaje || 'No se pudo actualizar'); return; }
        alert(`Actualizados: ${data.resultado.actualizados}`);
        await cargarEntradasPagos();
    } catch (e) { console.error(e); alert('Error de comunicación'); }
}

document.addEventListener('DOMContentLoaded', () => {
    cargarEntradasPagos();
    qs(document, '#btnBuscar')?.addEventListener('click', cargarEntradasPagos);
    qs(document, '#filtroCredito')?.addEventListener('change', cargarEntradasPagos);
    qs(document, '#filtroPagado')?.addEventListener('change', cargarEntradasPagos);
    qs(document, '#busqueda')?.addEventListener('keydown', e => { if (e.key === 'Enter') cargarEntradasPagos(); });
    qs(document, '#btnMarcarPagado')?.addEventListener('click', marcarPagados);
    qs(document, '#seleccionarTodo')?.addEventListener('click', () => seleccionarTodo(true));
    qs(document, '#deseleccionarTodo')?.addEventListener('click', () => seleccionarTodo(false));
    qs(document, '#checkAll')?.addEventListener('change', e => seleccionarTodo(!!e.target.checked));
});

