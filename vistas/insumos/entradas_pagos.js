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

// Paginación y filtros avanzados
  let epPagina = 1;
  let epPageSize = 15;
  let epTotal = 0;

  // Preparados (credito NULL)
  let prepPagina = 1;
  let prepPageSize = 15;
  let prepTotal = 0;

  async function cargarEntradasPagosPaged(page = epPagina) {
    epPagina = page;
    const credito = qs(document, '#filtroCredito')?.value ?? '';
    const pagado = qs(document, '#filtroPagado')?.value ?? '';
    const q = qs(document, '#busqueda')?.value.trim() ?? '';
    const df = qs(document, '#dateFrom')?.value ?? '';
    const dt = qs(document, '#dateTo')?.value ?? '';
    const psSel = qs(document, '#epPageSize');
    epPageSize = psSel ? (parseInt(psSel.value, 10) || 15) : epPageSize;
    const params = new URLSearchParams();
    if (credito !== '') params.set('credito', credito);
    if (pagado !== '') params.set('pagado', pagado);
    if (q) params.set('q', q);
    if (df && dt) { params.set('date_from', df); params.set('date_to', dt); }
    params.set('page', String(epPagina));
    params.set('page_size', String(epPageSize));
    try {
        const resp = await fetch(`../../api/insumos/listar_entradas_pagos.php?${params.toString()}`);
        const data = await resp.json();
        if (!data.success) { alert(data.mensaje || 'Error al cargar'); return; }
        const rows = Array.isArray(data.resultado) ? data.resultado : (data.resultado?.rows || []);
        epTotal = (data.resultado && Number.isFinite(data.resultado.total)) ? data.resultado.total : rows.length;
        renderTabla(rows);
        renderPaginador();
    } catch (e) { console.error(e); alert('Error de comunicación'); }
  }

  // Listado de preparados (solo credito IS NULL)
  async function cargarPreparadosPaged(page = prepPagina) {
    prepPagina = page;
    const df = qs(document, '#prepDateFrom')?.value ?? '';
    const dt = qs(document, '#prepDateTo')?.value ?? '';
    const prod = qs(document, '#prepBuscarProd')?.value.trim() ?? '';
    const uni = qs(document, '#prepBuscarUnidad')?.value.trim() ?? '';
    const cmin = qs(document, '#prepCantMin')?.value ?? '';
    const cmax = qs(document, '#prepCantMax')?.value ?? '';
    const psSel = qs(document, '#prepPageSize');
    prepPageSize = psSel ? (parseInt(psSel.value, 10) || 15) : prepPageSize;
    const params = new URLSearchParams();
    if (df && dt) { params.set('date_from', df); params.set('date_to', dt); }
    if (prod) params.set('producto', prod);
    if (uni) params.set('unidad', uni);
    if (cmin !== '') params.set('cantidad_min', cmin);
    if (cmax !== '') params.set('cantidad_max', cmax);
    params.set('page', String(prepPagina));
    params.set('page_size', String(prepPageSize));
    try {
      const resp = await fetch(`../../api/insumos/listar_preparados.php?${params.toString()}`);
      const data = await resp.json();
      if (!data.success) { alert(data.mensaje || 'Error al cargar'); return; }
      const rows = Array.isArray(data.resultado) ? data.resultado : (data.resultado?.rows || []);
      prepTotal = (data.resultado && Number.isFinite(data.resultado.total)) ? data.resultado.total : rows.length;
      renderTablaPreparados(rows);
      renderPaginadorPreparados();
    } catch (e) { console.error(e); alert('Error de comunicación'); }
  }

  function renderTablaPreparados(rows) {
    const tb = qs(document, '#tablaPreparados tbody'); if (!tb) return; tb.innerHTML = '';
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${r.id}</td>
        <td>${r.fecha ?? ''}</td>
        <td>${r.producto ?? ''}</td>
        <td>${r.cantidad ?? ''}</td>
        <td>${r.unidad ?? ''}</td>
        <td>${fmt$(r.costo_total ?? '')}</td>
      `;
      tb.appendChild(tr);
    });
  }

  function renderPaginadorPreparados() {
    const pag = qs(document, '#prepPaginador'); if (!pag) return; pag.innerHTML = '';
    const totalPag = Math.max(1, Math.ceil(prepTotal / prepPageSize));
    const makeLi = (txt, disabled, onClick, active=false) => {
      const li = document.createElement('li');
      li.className = 'page-item' + (disabled ? ' disabled' : '') + (active ? ' active' : '');
      const a = document.createElement('a'); a.className = 'page-link'; a.href = '#'; a.textContent = txt;
      if (!disabled) a.addEventListener('click', (e)=>{ e.preventDefault(); onClick(); });
      li.appendChild(a); return li;
    };
    pag.appendChild(makeLi('Anterior', prepPagina<=1, ()=> cargarPreparadosPaged(prepPagina-1)));
    for (let p=1; p<= totalPag; p++) {
      pag.appendChild(makeLi(String(p), false, ()=> cargarPreparadosPaged(p), p===prepPagina));
    }
    pag.appendChild(makeLi('Siguiente', prepPagina>=totalPag, ()=> cargarPreparadosPaged(prepPagina+1)));
  }

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
        const c = (r && typeof r.credito !== 'undefined') ? String(r.credito).toLowerCase() : '';
        let tipo = 'Efectivo';
        if (c === '1' || c === 'credito') tipo = 'Crédito';
        else if (c === '0' || c === 'efectivo') tipo = 'Efectivo';
        else if (c === 'transferencia') tipo = 'Transferencia';
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

function renderPaginador() {
    const pag = qs(document, '#epPaginador');
    if (!pag) return;
    pag.innerHTML = '';
    const totalPag = Math.max(1, Math.ceil(epTotal / epPageSize));
    const makeLi = (txt, disabled, onClick, active=false) => {
        const li = document.createElement('li');
        li.className = 'page-item' + (disabled ? ' disabled' : '') + (active ? ' active' : '');
        const a = document.createElement('a'); a.className = 'page-link'; a.href = '#'; a.textContent = txt;
        if (!disabled) a.addEventListener('click', (e)=>{ e.preventDefault(); onClick(); });
        li.appendChild(a); return li;
    };
    pag.appendChild(makeLi('Anterior', epPagina<=1, ()=> cargarEntradasPagosPaged(epPagina-1)));
    for (let p=1; p<= totalPag; p++) {
        pag.appendChild(makeLi(String(p), false, ()=> cargarEntradasPagosPaged(p), p===epPagina));
    }
    pag.appendChild(makeLi('Siguiente', epPagina>=totalPag, ()=> cargarEntradasPagosPaged(epPagina+1)));
}

async function buscarNota() {
    const notaEl = qs(document, '#notaBuscar');
    const n = notaEl ? parseInt(notaEl.value, 10) : 0;
    const txtEl = qs(document, '#notaBuscarTexto');
    const t = txtEl ? String(txtEl.value || '').trim() : '';
    if (t) {
        try {
            const params = new URLSearchParams();
            params.set('q', t);
            const resp = await fetch(`../../api/insumos/consultar_nota_compra.php?${params.toString()}`);
            const data = await resp.json();
            if (!data.success) { alert(data.mensaje || 'Sin resultados'); return; }
            const rows = Array.isArray(data.resultado) ? data.resultado : [];
            const tb = qs(document, '#tablaNotaResultados tbody');
            if (tb) {
                tb.innerHTML = '';
                rows.forEach(r => {
                    const tr = document.createElement('tr');
                    const c = (r && typeof r.credito !== 'undefined') ? String(r.credito).toLowerCase() : '';
                    let tipo = 'Efectivo';
                    if (c === '1' || c === 'credito') tipo = 'Crdito';
                    else if (c === '0' || c === 'efectivo') tipo = 'Efectivo';
                    else if (c === 'transferencia') tipo = 'Transferencia';
                    tr.innerHTML = `
                        <td>${r.id}</td>
                        <td>${r.fecha ?? ''}</td>
                        <td>${r.proveedor ?? ''}</td>
                        <td>${r.producto ?? ''}</td>
                        <td>${r.cantidad ?? ''}</td>
                        <td>${r.unidad ?? ''}</td>
                        <td>${fmt$(r.costo_total ?? '')}</td>
                        <td>${tipo}</td>
                        <td>${r.nota ?? ''}</td>
                    `;
                    tb.appendChild(tr);
                });
            }
        } catch (e) { console.error(e); alert('Error al consultar la nota'); }
        return;
    }
    if ((!Number.isFinite(n) || n <= 0) && !t) { alert('Selecciona una nota o ingresa texto'); return; }
    try {
        const params = new URLSearchParams();
        if (Number.isFinite(n) && n > 0) params.set('nota', String(n));
        if (t) params.set('q', t);
        const resp = await fetch(`../../api/insumos/consultar_nota_compra.php?${params.toString()}`);
        const data = await resp.json();
        if (!data.success) { alert(data.mensaje || 'Sin resultados'); return; }
        const rows = Array.isArray(data.resultado) ? data.resultado : [];
        const tb = qs(document, '#tablaNotaResultados tbody');
        if (tb) {
            tb.innerHTML = '';
            rows.forEach(r => {
                const tr = document.createElement('tr');
                const c = (r && typeof r.credito !== 'undefined') ? String(r.credito).toLowerCase() : '';
                let tipo = 'Efectivo';
                if (c === '1' || c === 'credito') tipo = 'Crédito';
                else if (c === '0' || c === 'efectivo') tipo = 'Efectivo';
                else if (c === 'transferencia') tipo = 'Transferencia';
                tr.innerHTML = `
                    <td>${r.id}</td>
                    <td>${r.fecha ?? ''}</td>
                    <td>${r.proveedor ?? ''}</td>
                    <td>${r.producto ?? ''}</td>
                    <td>${r.cantidad ?? ''}</td>
                    <td>${r.unidad ?? ''}</td>
                    <td>${fmt$(r.costo_total ?? '')}</td>
                    <td>${tipo}</td>
                    <td>${r.nota ?? ''}</td>
                `;
                tb.appendChild(tr);
            });
        }
    } catch (e) { console.error(e); alert('Error al consultar la nota'); }
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
        await cargarEntradasPagosPaged();
    } catch (e) { console.error(e); alert('Error de comunicación'); }
}

  document.addEventListener('DOMContentLoaded', () => {
    // Cargar lista de notas para el select
    (async () => {
      try {
        const resp = await fetch('../../api/insumos/listar_notas.php');
        const data = await resp.json();
        if (data && data.success) {
          const sel = qs(document, '#notaBuscar');
          if (sel) {
            // limpiar, mantener opción "Todas"
            sel.innerHTML = '<option value="">Todas</option>';
            (data.resultado || []).forEach(r => {
              const v = (r && typeof r.nota !== 'undefined') ? r.nota : null;
              if (v !== null && v !== undefined) {
                const opt = document.createElement('option');
                opt.value = String(v);
                opt.textContent = String(v);
                sel.appendChild(opt);
              }
            });
          }
        }
      } catch (e) { console.error('Error cargando notas', e); }
    })();
    const ps = qs(document, '#epPageSize'); if (ps) ps.value = '15';
    cargarEntradasPagosPaged(1);
    qs(document, '#btnBuscar')?.addEventListener('click', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#filtroCredito')?.addEventListener('change', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#filtroPagado')?.addEventListener('change', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#busqueda')?.addEventListener('keydown', e => { if (e.key === 'Enter') cargarEntradasPagosPaged(1); });
    qs(document, '#dateFrom')?.addEventListener('change', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#dateTo')?.addEventListener('change', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#epPageSize')?.addEventListener('change', ()=> cargarEntradasPagosPaged(1));
    qs(document, '#btnMarcarPagado')?.addEventListener('click', marcarPagados);
    qs(document, '#seleccionarTodo')?.addEventListener('click', () => seleccionarTodo(true));
    qs(document, '#deseleccionarTodo')?.addEventListener('click', () => seleccionarTodo(false));
    qs(document, '#checkAll')?.addEventListener('change', e => seleccionarTodo(!!e.target.checked));
    qs(document, '#btnBuscarNota')?.addEventListener('click', buscarNota);
    qs(document, '#notaBuscar')?.addEventListener('change', () => buscarNota());
    qs(document, '#notaBuscarTexto')?.addEventListener('keydown', e => { if (e.key === 'Enter') buscarNota(); });

    // Preparados events
    const pps = qs(document, '#prepPageSize'); if (pps) pps.value = '15';
    cargarPreparadosPaged(1);
    qs(document, '#prepBtnBuscar')?.addEventListener('click', ()=> cargarPreparadosPaged(1));
    qs(document, '#prepDateFrom')?.addEventListener('change', ()=> cargarPreparadosPaged(1));
    qs(document, '#prepDateTo')?.addEventListener('change', ()=> cargarPreparadosPaged(1));
    qs(document, '#prepBuscarProd')?.addEventListener('keydown', e => { if (e.key === 'Enter') cargarPreparadosPaged(1); });
    qs(document, '#prepBuscarUnidad')?.addEventListener('keydown', e => { if (e.key === 'Enter') cargarPreparadosPaged(1); });
    qs(document, '#prepCantMin')?.addEventListener('change', ()=> cargarPreparadosPaged(1));
    qs(document, '#prepCantMax')?.addEventListener('change', ()=> cargarPreparadosPaged(1));
    qs(document, '#prepPageSize')?.addEventListener('change', ()=> cargarPreparadosPaged(1));
  });
