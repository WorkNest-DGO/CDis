function showAppMsg(msg) {
  const body = document.querySelector('#appMsgModal .modal-body');
  if (body) body.textContent = String(msg);
  if (typeof showModal === 'function') {
    showModal('#appMsgModal');
  } else {
    alert(String(msg));
  }
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

  // Toolbar refs
  const selOrigen = qs('#selInsumoOrigen');
  const selDestino = qs('#selInsumoDestino');
  const inpCantidad = qs('#inpCantidadOrigen');
  const inpObs = qs('#inpObsProc');
  const btnCrear = qs('#btnCrearLote');

  let cache = [];

  const allowedNext = {
    pendiente: 'en_preparacion',
    en_preparacion: 'listo',
    listo: 'entregado'
  };

  function escapeHtml(s){
    const div = document.createElement('div');
    div.innerText = s != null ? String(s) : '';
    return div.innerHTML;
  }

  function render(items){
    Object.values(cols).forEach(c => c && (c.innerHTML = ''));
    (items || []).forEach(p => {
      const card = document.createElement('div');
      card.className = 'kanban-item';
      card.draggable = true;
      card.dataset.id = p.id;
      card.dataset.estado = p.estado;
      card.innerHTML = `
        <div class="title">${escapeHtml(p.insumo_origen)} → ${escapeHtml(p.insumo_destino)}</div>
        <div class="meta"><span>${escapeHtml(p.cantidad_origen)} ${escapeHtml(p.unidad_origen || '')}</span> <span>#${p.id}</span></div>
        <div class="badges">
          ${p.entrada_insumo_id ? `<span>Entrada #${p.entrada_insumo_id}</span>` : ''}
          ${p.mov_salida_id ? `<span>Salida #${p.mov_salida_id}</span>` : ''}
        </div>
        ${p.qr_path ? `<button class="btn-qr" data-src="${escapeHtml(p.qr_path)}">QR</button>` : ''}
      `;
      bindDrag(card);
      const col = cols[p.estado] || cols.pendiente;
      if (col) col.appendChild(card);
      const btnQr = card.querySelector('.btn-qr');
      if (btnQr){
        btnQr.addEventListener('click', () => {
          const src = btnQr.getAttribute('data-src');
          if (src) window.open('../../' + src.replace(/^\/+/, ''), '_blank');
        });
      }
    });
  }

  function bindDrag(el){
    el.addEventListener('dragstart', ev => {
      ev.dataTransfer.setData('text/plain', el.dataset.id);
      setTimeout(()=> el.classList.add('dragging'), 0);
    });
    el.addEventListener('dragend', ()=> el.classList.remove('dragging'));
  }

  qsa('.kanban-dropzone').forEach(zone => {
    zone.addEventListener('dragover', ev => { ev.preventDefault(); zone.classList.add('drag-over'); });
    zone.addEventListener('dragleave', ()=> zone.classList.remove('drag-over'));
    zone.addEventListener('drop', async ev => {
      ev.preventDefault();
      zone.classList.remove('drag-over');
      const id = parseInt(ev.dataTransfer.getData('text/plain'), 10);
      const card = document.querySelector(`.kanban-item[data-id='${id}']`);
      if (!card) return;
      const current = card.dataset.estado;
      const nuevoEstado = zone.closest('.kanban-board').dataset.status;
      if (allowedNext[current] !== nuevoEstado){
        alert('Transición no permitida');
        return;
      }

      // Si pasa a listo, primero hacer move a listo y luego completar
      if (nuevoEstado === 'listo'){
        const okMove = await apiMove(id, 'listo');
        if (!okMove) return;
        const cantidad = window.prompt('Cantidad resultante del destino:', '');
        if (cantidad && !isNaN(Number(cantidad)) && Number(cantidad) > 0){
          const comp = await apiComplete(id, Number(cantidad));
          if (!comp) return;
          // actualizar card con info
          const idx = cache.findIndex(x => x.id === id);
          if (idx >= 0){
            cache[idx].estado = 'listo';
            cache[idx].entrada_insumo_id = comp.entrada_insumo_id;
            cache[idx].mov_salida_id = comp.mov_salida_id;
            cache[idx].qr_path = comp.qr_path;
          }
          card.dataset.estado = 'listo';
          zone.appendChild(card);
          render(cache); // re-render para mostrar badges/QR
        } else {
          // Solo mover a listo sin completar
          const idx = cache.findIndex(x => x.id === id);
          if (idx >= 0) cache[idx].estado = 'listo';
          card.dataset.estado = 'listo';
          zone.appendChild(card);
        }
        return;
      }

      const ok = await apiMove(id, nuevoEstado);
      if (ok){
        const idx = cache.findIndex(x => x.id === id);
        if (idx >= 0) cache[idx].estado = nuevoEstado;
        card.dataset.estado = nuevoEstado;
        zone.appendChild(card);
      }
    });
  });

  async function loadInsumos(){
    const r = await fetch('../../api/insumos/listar_insumos.php');
    if (!r.ok) { alert('Error al cargar insumos'); return; }
    const j = await r.json();
    const lista = j.resultado || j.items || j.data || [];
    const opts = ['<option value="">Seleccione...</option>'].concat(lista.map(i => `<option value="${i.id}">${i.nombre} (${i.unidad || ''})</option>`));
    if (selOrigen) selOrigen.innerHTML = opts.join('');
    if (selDestino) selDestino.innerHTML = opts.join('');
  }

  async function cargarProcesos(){
    const r = await fetch('../../api/cocina/procesado.php?action=list');
    if (!r.ok) { alert('Error al cargar procesos'); return; }
    const j = await r.json();
    cache = j.items || j.resultado || [];
    render(cache);
  }

  async function apiMove(id, nuevo_estado){
    try{
      const r = await fetch('../../api/cocina/procesado.php?action=move', {
        method: 'PATCH',
        headers: { 'Content-Type':'application/json' },
        body: JSON.stringify({ id, nuevo_estado })
      });
      const j = await r.json();
      if (!r.ok || j.success === false){
        alert(j.mensaje || 'No se pudo mover');
        return false;
      }
      return true;
    }catch(e){ alert('Error de red'); return false; }
  }

  async function apiComplete(id, cantidad_resultante){
    try{
      const fd = new FormData();
      fd.append('id', String(id));
      fd.append('cantidad_resultante', String(cantidad_resultante));
      const r = await fetch('../../api/cocina/procesado.php?action=complete', { method: 'POST', body: fd });
      const j = await r.json();
      if (!r.ok || j.success === false){
        alert(j.mensaje || 'No se pudo completar');
        return null;
      }
      return j;
    }catch(e){ alert('Error de red'); return null; }
  }

  async function crearLote(){
    const o = parseInt(selOrigen.value, 10) || 0;
    const d = parseInt(selDestino.value, 10) || 0;
    const c = parseFloat(String(inpCantidad.value).replace(',', '.')) || 0;
    const obs = (inpObs.value || '').trim();
    if (!o || !d){ alert('Seleccione insumos de origen y destino'); return; }
    if (o === d){ alert('El origen y el destino no pueden ser iguales'); return; }
    if (c <= 0){ alert('Cantidad inválida'); return; }
    const fd = new FormData();
    fd.append('insumo_origen_id', String(o));
    fd.append('insumo_destino_id', String(d));
    fd.append('cantidad_origen', String(c));
    if (obs) fd.append('observaciones', obs);
    const r = await fetch('../../api/cocina/procesado.php?action=create', { method:'POST', body: fd });
    const j = await r.json();
    if (!r.ok || j.success === false){ alert(j.mensaje || 'No se pudo crear'); return; }
    await cargarProcesos();
    inpCantidad.value = '';
    inpObs.value = '';
  }

  // Long-poll de cambios para auto-actualizar tarjetas (usa listen_cambios)
  let cocinaVersion = Number(localStorage.getItem('cocinaVersion') || '0');
  async function waitCambiosLoop(){
    try{
      const r = await fetch(`../../api/cocina/listen_cambios.php?since=${cocinaVersion}`, { cache:'no-store' });
      const data = await r.json();
      if (data && data.changed){
        cocinaVersion = Number(data.version) || cocinaVersion;
        localStorage.setItem('cocinaVersion', String(cocinaVersion));
        await cargarProcesos();
      }
    }catch(e){
      await new Promise(res => setTimeout(res, 800));
    }
    // relanzar
    waitCambiosLoop();
  }

  if (btnCrear) btnCrear.addEventListener('click', crearLote);
  // Iniciar long-poll sin depender del rol ni de cargas previas
  try { waitCambiosLoop(); } catch(e) { /* noop */ }
  // Cargas iniciales de datos (no bloquean el long-poll)
  loadInsumos().then(cargarProcesos).catch(()=>{});
})();
