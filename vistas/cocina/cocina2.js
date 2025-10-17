// Preservar alert nativo para evitar recursividad
const __nativeAlert = typeof window !== 'undefined' && window.alert ? window.alert.bind(window) : null;
function showAppMsg(msg) {
  const body = document.querySelector('#appMsgModal .modal-body');
  if (body) body.textContent = String(msg);
  try { if (window.$ && $.fn && $.fn.modal) { $('#appMsgModal').modal('show'); return; } } catch(e) {}
  const modal = document.getElementById('appMsgModal');
  if (modal) { modal.classList.add('show'); modal.style.display = 'block'; modal.removeAttribute('aria-hidden'); return; }
  if (__nativeAlert) { __nativeAlert(String(msg)); } else { try { console.error(String(msg)); } catch(e) {} }
}
window.alert = showAppMsg;

(() => {
  const qs = s => document.querySelector(s);
  const qsa = s => Array.from(document.querySelectorAll(s));

  const cols = {
    pendiente: qs('#col-pendiente'),
    en_preparacion: qs('#col-preparacion'),
    listo: qs('#col-listo'),
    entregado: qs('#col-entregado')
  };

  // UI refs (grupo)
  const origenesContainer = qs('#origenesContainer');
  const btnAddOrigen = qs('#btnAddOrigen');
  const selDestinoGrupo = qs('#selInsumoDestinoGrupo');
  const inpObsGrupo = qs('#inpObsProcGrupo');
  const btnCrearGrupo = qs('#btnCrearGrupo');
  const selImpresora = qs('#selImpresoraCocina');

  let cache = [];
  let grupoActual = null; // para completar grupo

  const allowedNext = { pendiente: 'en_preparacion', en_preparacion:'listo', listo:'entregado' };

  function escapeHtml(s){ const div = document.createElement('div'); div.innerText = s != null ? String(s) : ''; return div.innerHTML; }

  function render(items){
    Object.values(cols).forEach(c => c && (c.innerHTML = ''));
    (items || []).forEach(g => {
      const card = document.createElement('div');
      card.className = 'kanban-item';
      card.draggable = true;
      card.dataset.pedido = g.pedido;
      card.dataset.estado = g.estado;
      const origenesHtml = (g.procesos||[]).map(o => `${escapeHtml(o.insumo_origen)} (${escapeHtml(o.cantidad_origen)} ${escapeHtml(o.unidad_origen||'')})`).join(', ');
      const mermaTotal = (g.procesos||[]).reduce((acc, p) => acc + ((p.merma_qrs || []).length), 0);
      card.innerHTML = `
        <div class="title">#${g.pedido} → ${escapeHtml(g.destino)}</div>
        <div class="meta"><span>${escapeHtml(origenesHtml)}</span></div>
        <div style="color:black" class="badges">
          ${g.entrada_insumo_id ? `<span>Entrada #${g.entrada_insumo_id}</span>` : ''}
        </div>
        ${g.qr_path ? `<button class="btn-qr" data-src="${escapeHtml(g.qr_path)}">QR</button>` : ''}
        ${(g.estado === 'entregado' && mermaTotal > 0) ? `<button class="btn-merma" data-pedido="${g.pedido}">Mermas</button>` : ''}
        ${g.estado === 'listo' && !g.entrada_insumo_id ? `<button class="btn-completar-grupo" data-pedido="${g.pedido}">Completar</button>` : ''}
      `;
      bindDragGroup(card);
      const col = cols[g.estado] || cols.pendiente; if (col) col.appendChild(card);
      card.querySelector('.btn-qr')?.addEventListener('click', async ()=>{
        const src = card.querySelector('.btn-qr')?.getAttribute('data-src'); if (src) window.open('../../' + src.replace(/^\/+/, ''), '_blank');
        try {
          const eid = Number(g.entrada_insumo_id || 0);
          if (eid > 0){
            let url = '../../api/insumos/imprimir_qrs_entrada.php';
            const v = (selImpresora && selImpresora.value) ? selImpresora.value : '';
            if (v) url += ('?printer_ip=' + encodeURIComponent(v));
            await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ entrada_ids: [eid] }) });
          }
        } catch(e) {}
      });
      card.querySelector('.btn-merma')?.addEventListener('click', ()=>{ mostrarMermaQrModal(g); });
      card.querySelector('.btn-completar-grupo')?.addEventListener('click', ()=>{ grupoActual = g; ensureCompletarGrupoModal(g); });
    });
  }

  function bindDragGroup(el){
    el.addEventListener('dragstart', ev => { ev.dataTransfer.setData('text/plain', el.dataset.pedido); setTimeout(()=> el.classList.add('dragging'), 0); });
    el.addEventListener('dragend', ()=> el.classList.remove('dragging'));
  }

  qsa('.kanban-dropzone').forEach(zone => {
    zone.addEventListener('dragover', ev => { ev.preventDefault(); zone.classList.add('drag-over'); });
    zone.addEventListener('dragleave', ()=> zone.classList.remove('drag-over'));
    zone.addEventListener('drop', async ev => {
      ev.preventDefault(); zone.classList.remove('drag-over');
      const pedido = parseInt(ev.dataTransfer.getData('text/plain'), 10);
      const card = document.querySelector(`.kanban-item[data-pedido='${pedido}']`);
      if (!card) return;
      const current = card.dataset.estado;
      const nuevoEstado = zone.closest('.kanban-board').dataset.status;
      if (allowedNext[current] !== nuevoEstado){ alert('Transición no permitida'); return; }
      if (nuevoEstado === 'listo'){
        const okMove = await apiMoveGrupo(pedido, 'listo'); if (!okMove) return;
        grupoActual = cache.find(x => x.pedido === pedido) || null; if (grupoActual) ensureCompletarGrupoModal(grupoActual);
        return;
      }
      const ok = await apiMoveGrupo(pedido, nuevoEstado);
      if (ok){ const idx = cache.findIndex(x => x.pedido === pedido); if (idx >= 0) cache[idx].estado = nuevoEstado; card.dataset.estado = nuevoEstado; zone.appendChild(card); }
    });
  });

  function buildOrigenRow(insumos){
    const row = document.createElement('div'); row.className = 'd-flex gap-2 align-items-end my-1';
    row.innerHTML = `
      <div style="flex:2;">
        <label>Insumo</label>
        <div class="selector-insumo position-relative">
          <input type="text" class="form-control buscador-insumo" placeholder="Buscar insumo...">
          <select class="form-control selOrigen d-none"></select>
          <ul class="list-group lista-insumos position-absolute w-100" style="z-index:1000;"></ul>
        </div>
      </div>
      <div style="flex:1;">
        <label>Cantidad</label>
        <input type="number" step="0.01" min="0.01" class="form-control inpCant" placeholder="0.00">
      </div>
      <div>
        <button type="button" class="btn btn-danger btn-sm btnRemove">-</button>
      </div>`;
    // Poblar el select oculto con el catálogo para mantener unidad en la etiqueta
    const sel = row.querySelector('.selOrigen');
    sel.innerHTML = ['<option value="">Seleccione...</option>']
      .concat((insumos||[]).map(i => `<option value="${i.id}">${i.nombre} (${i.unidad||''})</option>`))
      .join('');
    // Inicializar buscador tipo autocomplete
    try { inicializarBuscadorOrigen(row, insumos); } catch(e) { /* noop */ }
    row.querySelector('.btnRemove').addEventListener('click', ()=> row.remove());
    return row;
  }

  // Autocompletado para Destino (similar a insumo en entradas)
  function inicializarBuscadorDestino(select, insumos){
    if (!select) return;
    // Si ya fue inicializado, solo refrescar dataset para búsqueda
    let cont = select.previousElementSibling;
    const isCont = cont && cont.classList && cont.classList.contains('selector-destino');
    if (!isCont){
      // Crear contenedor y elementos de UI
      cont = document.createElement('div');
      cont.className = 'selector-insumo position-relative selector-destino';
      const input = document.createElement('input');
      input.type = 'text'; input.className = 'form-control buscador-destino'; input.placeholder = 'Buscar destino...';
      const ul = document.createElement('ul');
      ul.className = 'list-group lista-destino position-absolute w-100'; ul.style.zIndex = '1000'; ul.style.display = 'none';
      cont.appendChild(input); cont.appendChild(ul);
      // Insertar antes del select y ocultar select
      if (select.parentElement) select.parentElement.insertBefore(cont, select);
      select.classList.add('d-none');
    }
    const input = cont.querySelector('.buscador-destino');
    const lista = cont.querySelector('.lista-destino');
    if (!input || !lista) return;
    if (input.dataset.autocompleteInitialized === 'true') return;
    input.dataset.autocompleteInitialized = 'true';

    const normalizar = (s) => {
      try { return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase(); } catch(e) { return String(s || '').toLowerCase(); }
    };
    const getNombre = (i) => (i && i.nombre) ? i.nombre : '';

    input.addEventListener('input', () => {
      const val = normalizar(input.value);
      lista.innerHTML = '';
      if (!val) { lista.style.display = 'none'; return; }
      const coincidencias = (insumos || []).filter(i => normalizar(getNombre(i)).includes(val)).slice(0, 50);
      coincidencias.forEach(i => {
        const li = document.createElement('li');
        li.className = 'list-group-item list-group-item-action';
        li.textContent = i.nombre + (i.unidad ? '' : '');
        li.addEventListener('click', () => {
          input.value = i.nombre;
          select.value = String(i.id);
          try { select.dispatchEvent(new Event('change')); } catch(_) {}
          lista.innerHTML = ''; lista.style.display = 'none';
        });
        lista.appendChild(li);
      });
      lista.style.display = coincidencias.length ? 'block' : 'none';
    });

    document.addEventListener('click', (e) => {
      if (!cont.contains(e.target)) { lista.style.display = 'none'; }
    });

    // Inicializar texto si ya hay valor seleccionado
    if (select.value) {
      const it = (insumos || []).find(c => String(c.id) === String(select.value));
      if (it) input.value = it.nombre || '';
    }
  }

  // Autocompletado similar a insumos.php para seleccionar insumo de origen
  function inicializarBuscadorOrigen(row, insumos){
    const cont = row.querySelector('.selector-insumo');
    if (!cont) return;
    const input = cont.querySelector('.buscador-insumo');
    const lista = cont.querySelector('.lista-insumos');
    const select = cont.querySelector('.selOrigen');
    if (!input || !lista || !select || input.dataset.autocompleteInitialized) return;
    input.dataset.autocompleteInitialized = 'true';

    const normalizar = (s) => {
      try { return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase(); } catch(e) { return String(s || '').toLowerCase(); }
    };

    input.addEventListener('input', () => {
      const val = normalizar(input.value);
      lista.innerHTML = '';
      if (!val) { lista.style.display = 'none'; return; }
      const coincidencias = (insumos || [])
        .filter(i => normalizar(i.nombre).includes(val))
        .slice(0, 50);
      coincidencias.forEach(i => {
        const li = document.createElement('li');
        li.className = 'list-group-item list-group-item-action';
        li.textContent = `${i.nombre}`;
        li.addEventListener('click', () => {
          input.value = i.nombre;
          select.value = String(i.id);
          try { select.dispatchEvent(new Event('change')); } catch(_) {}
          lista.innerHTML = '';
          lista.style.display = 'none';
        });
        lista.appendChild(li);
      });
      lista.style.display = coincidencias.length ? 'block' : 'none';
    });

    document.addEventListener('click', (e) => {
      if (!cont.contains(e.target)) { lista.style.display = 'none'; }
    });

    // Si ya hay valor seleccionado, rellenar input
    if (select.value) {
      const it = (insumos||[]).find(c => String(c.id) === String(select.value));
      if (it) input.value = it.nombre || '';
    }
  }

  async function loadInsumos(){
    const r = await fetch('../../api/insumos/listar_insumos.php'); if (!r.ok) { alert('Error al cargar insumos'); return; }
    const j = await r.json(); const lista = j.resultado || j.items || j.data || [];
    const opts = ['<option value="">Seleccione...</option>'].concat(lista.map(i => `<option value=\"${i.id}\">${i.nombre} (${i.unidad || ''})</option>`));
    if (selDestinoGrupo) {
      selDestinoGrupo.innerHTML = opts.join('');
      try { inicializarBuscadorDestino(selDestinoGrupo, lista); } catch(e) {}
    }
    if (origenesContainer){ origenesContainer.innerHTML = ''; origenesContainer.appendChild(buildOrigenRow(lista)); btnAddOrigen && (btnAddOrigen.onclick = ()=> origenesContainer.appendChild(buildOrigenRow(lista))); }
  }

  async function cargarProcesos(){
    const r = await fetch('../../api/cocina/listar_grupos.php'); if (!r.ok) { alert('Error al cargar procesos'); return; }
    const j = await r.json(); cache = j.grupos || []; render(cache);
  }

  async function apiMoveGrupo(pedido, nuevo_estado){
    try{ const r = await fetch('../../api/cocina/mover_grupo.php', { method:'PATCH', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ pedido, nuevo_estado }) }); const j = await r.json(); if (!r.ok || j.success === false){ alert(j.mensaje || 'No se pudo mover'); return false; } return true; }catch(e){ alert('Error de red'); return false; }
  }

  async function imprimirMermaQr(movIds, triggerBtn){
    if (!Array.isArray(movIds) || movIds.length === 0){ alert('Sin movimientos para imprimir'); return; }
    const btn = triggerBtn || null;
    if (btn) btn.disabled = true;
    try {
      let url = '../../api/cocina/imprimir_qrs_merma.php';
      try { const v = (selImpresora && selImpresora.value) ? selImpresora.value : ''; if (v) url += ('?printer_ip=' + encodeURIComponent(v)); } catch(e) {}
      const r = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ movimiento_ids: movIds }) });
      let j = null;
      try { j = await r.json(); } catch(e) { j = null; }
      if (!r.ok || !j || j.success === false){
        const msg = (j && (j.mensaje || (j.resultado && j.resultado.mensaje))) || 'No se pudo imprimir';
        throw new Error(msg);
      }
      const impresos = (j.resultado && typeof j.resultado.impresos !== 'undefined') ? j.resultado.impresos : (typeof j.impresos !== 'undefined' ? j.impresos : movIds.length);
      alert(`Se envió a imprimir ${impresos} QR${impresos === 1 ? '' : 's'} de merma.`);
    } catch (err) {
      alert(err && err.message ? err.message : 'Error al imprimir');
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  async function apiCompleteGrupo(pedido, cantidad_resultante, mermas, motivo){
    try{ const r = await fetch('../../api/cocina/completar_grupo.php', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ pedido, cantidad_resultante, mermas, motivo_merma: motivo||'' }) }); const j = await r.json(); if (!r.ok || j.success === false){ alert(j.mensaje || 'No se pudo completar'); return null; } return j; }catch(e){ alert('Error de red'); return null; }
  }

  async function crearGrupo(){
    const d = parseInt(selDestinoGrupo?.value || '0', 10) || 0; const obs = (inpObsGrupo?.value || '').trim(); if (!d){ alert('Seleccione insumo destino'); return; }
    const rows = Array.from(origenesContainer?.querySelectorAll('.d-flex') || []); const origenes = [];
    for (const row of rows){ const sel = row.querySelector('.selOrigen'); const inp = row.querySelector('.inpCant'); const iid = parseInt(sel?.value || '0', 10) || 0; const cant = parseFloat(String(inp?.value || '0').replace(',', '.')) || 0; if (!iid || !(cant>0)) continue; const unidad = (sel?.selectedOptions[0]?.textContent || '').split('(')[1]?.replace(')','').trim() || ''; origenes.push({ insumo_id: iid, cantidad: cant, unidad }); }
    if (origenes.length === 0){ alert('Agregue al menos un origen válido'); return; }
    const unidadDestino = (selDestinoGrupo?.selectedOptions[0]?.textContent || '').split('(')[1]?.replace(')','').trim() || '';
    const body = { destino_id: d, unidad_destino: unidadDestino, observaciones: obs, origenes };
    const r = await fetch('../../api/cocina/crear_grupo.php', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) }); const j = await r.json(); if (!r.ok || j.success === false){ alert(j.mensaje || 'No se pudo crear'); return; }
    await cargarProcesos(); if (inpObsGrupo) inpObsGrupo.value = '';
    // Limpiar filas excepto una
    const jr = await fetch('../../api/insumos/listar_insumos.php'); const lj = await jr.json(); const lista = lj.resultado || lj.items || lj.data || [];
    if (origenesContainer){ origenesContainer.innerHTML = ''; origenesContainer.appendChild(buildOrigenRow(lista)); }
  }

  // Long-poll de cambios para auto-actualizar tarjetas (usa listen_cambios)
  let cocinaVersion = Number(localStorage.getItem('cocinaVersion') || '0');
  async function waitCambiosLoop(){
    try{ const r = await fetch(`../../api/cocina/listen_cambios.php?since=${cocinaVersion}`, { cache:'no-store' }); const data = await r.json(); if (data && data.changed){ cocinaVersion = Number(data.version) || cocinaVersion; localStorage.setItem('cocinaVersion', String(cocinaVersion)); await cargarProcesos(); } }
    catch(e){ await new Promise(res => setTimeout(res, 800)); }
    waitCambiosLoop();
  }

  if (btnCrearGrupo) btnCrearGrupo.addEventListener('click', crearGrupo);
  try { waitCambiosLoop(); } catch(e) { /* noop */ }
  // Watch de corte abierto: alternar visibilidad
  async function watchCorte(){
    try{
      const r = await fetch('../../api/insumos/cortes_almacen.php?accion=listar', { cache:'no-store' });
      const j = await r.json(); let abierto = false;
      if (j && j.success && Array.isArray(j.resultado)){
        abierto = j.resultado.some(c => c && (c.fecha_fin === null || String(c.fecha_fin).trim() === ''));
      }
      const rol = (document.getElementById('user-info')?.dataset.rol || '').toLowerCase();
      const puede = (rol === 'admin' || rol === 'supervisor');
      const sec = document.getElementById('sec-crear-grupo');
      const al  = document.getElementById('alert-sin-corte-lote');
      if (sec) sec.style.display = (puede && abierto) ? '' : 'none';
      if (al)  al.style.display  = (!abierto) ? '' : 'none';
    }catch(e){ /* noop */ }
    setTimeout(watchCorte, 8000);
  }
  try { watchCorte(); } catch(e) {}
  loadInsumos().then(cargarProcesos).catch(()=>{});

  // Cargar impresoras
  function cargarImpresoras($sel){
    fetch('../../api/impresoras/listar.php', {cache:'no-store'})
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
      }).catch(()=>{});
  }
  try { if (selImpresora) cargarImpresoras(selImpresora); } catch(e) {}

  // Modal completar grupo
  function ensureCompletarGrupoModal(g){
    let modal = qs('#modalCompletarProc');
    if (!modal){
      const html = `
      <div class="modal fade" id="modalCompletarProc" tabindex="-1" role="dialog" aria-hidden="true">
        <div class="modal-dialog" role="document">
          <div style="color:black" class="modal-content">
            <div class="modal-header">
              <h5 style="color:black" class="modal-title">Completar grupo</h5>
              <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body">
              <div class="form-group">
                <label>Grupo (pedido → destino)</label>
                <div id="cmpResumen"></div>
              </div>
              <div class="form-group">
                <label for="cmpCantidadRes">Cantidad resultante</label>
                <input id="cmpCantidadRes" type="number" step="0.01" min="0.01" class="form-control" placeholder="0.00">
              </div>
              <div class="form-group">
                <label>Mermas por origen</label>
                <div id="cmpMermasList"></div>
              </div>
              <div class="form-group">
                <label for="cmpMotivo">Motivo de merma (opcional)</label>
                <input id="cmpMotivo" type="text" class="form-control" placeholder="Describa el motivo">
              </div>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancelar</button>
              <button type="button" class="btn custom-btn" id="cmpBtnConfirm">Confirmar</button>
            </div>
          </div>
        </div>
      </div>`;
      const wrap = document.createElement('div'); wrap.innerHTML = html; document.body.appendChild(wrap.firstElementChild); modal = qs('#modalCompletarProc');
      modal.querySelector('.close')?.addEventListener('click', ()=> hideModal(modal));
      modal.querySelector('.btn-secondary')?.addEventListener('click', ()=> hideModal(modal));
    }
    const resumen = qs('#cmpResumen'); const inp = qs('#cmpCantidadRes'); const mlist = qs('#cmpMermasList');
    if (resumen) resumen.textContent = `#${g.pedido} → ${g.destino}`;
    if (inp) inp.value = '';
    if (mlist){
      mlist.innerHTML = '';
      (g.procesos||[]).forEach(p => {
        const row = document.createElement('div'); row.className = 'd-flex gap-2 align-items-center my-1';
        row.innerHTML = `<div style="flex:2;">${escapeHtml(p.insumo_origen)} (${escapeHtml(p.cantidad_origen)} ${escapeHtml(p.unidad_origen||'')})</div><div style=\"flex:1;\"><input type=\"number\" step=\"0.01\" min=\"0\" class=\"form-control inpMerma\" data-proceso-id=\"${p.id}\" placeholder=\"Merma\"></div>`;
        mlist.appendChild(row);
      });
    }
    const btn = qs('#cmpBtnConfirm');
    if (btn){
      btn.onclick = async ()=>{
        const val = parseFloat((qs('#cmpCantidadRes')?.value || '0')) || 0; if (!(val > 0)) { alert('Capture una cantidad válida'); return; }
        const mermas = Array.from((qs('#cmpMermasList')?.querySelectorAll('.inpMerma')) || []).map(i => ({ proceso_id: parseInt(i.dataset.procesoId||'0',10)||0, cantidad: parseFloat(i.value||'0')||0 }));
        const motivo = (qs('#cmpMotivo')?.value || '').trim();
        const comp = await apiCompleteGrupo(g.pedido, val, mermas, motivo); if (!comp) return; hideModal(modal); await cargarProcesos();
      };
    }
    showModal(modal);
  }

  function mostrarMermaQrModal(grupo){
    if (!grupo) return;
    let modal = qs('#modalMermaQr');
    if (!modal){
      const html = `
      <div class="modal fade" id="modalMermaQr" tabindex="-1" role="dialog" aria-hidden="true">
        <div class="modal-dialog" role="document">
          <div style="color:black" class="modal-content">
            <div class="modal-header">
              <h5 style="color:black" class="modal-title">Mermas del pedido</h5>
              <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body"></div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
            </div>
          </div>
        </div>
      </div>`;
      const wrap = document.createElement('div'); wrap.innerHTML = html; document.body.appendChild(wrap.firstElementChild); modal = qs('#modalMermaQr');
      modal.querySelector('.close')?.addEventListener('click', ()=> hideModal(modal));
      modal.querySelector('.btn-secondary')?.addEventListener('click', ()=> hideModal(modal));
    }
    const title = modal.querySelector('.modal-title');
    if (title) title.textContent = `Mermas del pedido #${grupo.pedido}`;
    const body = modal.querySelector('.modal-body');
    if (body){
      body.innerHTML = '';
      const total = (grupo.procesos||[]).reduce((acc, p) => acc + ((p.merma_qrs || []).length), 0);
      if (!total){
        body.innerHTML = '<p>No hay mermas registradas para este grupo.</p>';
      } else {
        (grupo.procesos||[]).forEach(p => {
          const qrs = (p.merma_qrs||[]).filter(q => q && q.qr);
          if (!qrs.length) return;
          const section = document.createElement('div');
          section.className = 'merma-section mb-3';
          const header = document.createElement('h6');
          header.textContent = `${p.insumo_origen} (${p.cantidad_origen} ${p.unidad_origen || ''})`;
          section.appendChild(header);
          const grid = document.createElement('div');
          grid.className = 'merma-qr-grid';
          qrs.forEach((qrObj, idx) => {
            const rel = String(qrObj.qr || '');
            if (!rel) return;
            const path = '../../' + rel.replace(/^\/+/, '');
            const itemWrap = document.createElement('div');
            itemWrap.className = 'merma-qr-item';
            const link = document.createElement('a');
            link.href = path;
            link.target = '_blank';
            link.rel = 'noopener';
            link.title = 'Abrir QR en una nueva pestaña';
            const img = document.createElement('img');
            img.src = path;
            img.alt = `QR merma ${p.insumo_origen}`;
            img.loading = 'lazy';
            link.appendChild(img);
            itemWrap.appendChild(link);
            const movId = Number(qrObj.movimiento_id || qrObj.id || 0);
            const btnPrint = document.createElement('button');
            btnPrint.type = 'button';
            btnPrint.className = 'btn btn-sm btn-primary merma-qr-print-btn';
            btnPrint.textContent = 'Imprimir';
            if (movId > 0) {
              btnPrint.addEventListener('click', () => imprimirMermaQr([movId], btnPrint));
            } else {
              btnPrint.disabled = true;
              btnPrint.title = 'Movimiento no disponible';
            }
            itemWrap.appendChild(btnPrint);
            grid.appendChild(itemWrap);
          });
          section.appendChild(grid);
          body.appendChild(section);
        });
      }
    }
    showModal(modal);
  }

  // Helpers modal
  function showModal(selOrEl){ const el = typeof selOrEl === 'string' ? qs(selOrEl) : selOrEl; if (!el) return; if (window.$ && $.fn && $.fn.modal) { $(el).modal('show'); return; } el.classList.add('show'); el.style.display = 'block'; el.removeAttribute('aria-hidden'); }
  function hideModal(selOrEl){ const el = typeof selOrEl === 'string' ? qs(selOrEl) : selOrEl; if (!el) return; if (window.$ && $.fn && $.fn.modal) { $(el).modal('hide'); return; } el.classList.remove('show'); el.style.display = 'none'; el.setAttribute('aria-hidden', 'true'); }
})();
