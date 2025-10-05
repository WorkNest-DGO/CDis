// Preservar alert nativo para evitar recursividad
const __nativeAlert = typeof window !== 'undefined' && window.alert ? window.alert.bind(window) : null;
function showAppMsg(msg) {
  const body = document.querySelector('#appMsgModal .modal-body');
  if (body) body.textContent = String(msg);
  // Intentar abrir modal con jQuery si existe
  try {
    if (window.$ && $.fn && $.fn.modal) {
      $('#appMsgModal').modal('show');
      return;
    }
  } catch(e) {}
  // Fallback manual si el modal existe
  const modal = document.getElementById('appMsgModal');
  if (modal) {
    modal.classList.add('show');
    modal.style.display = 'block';
    modal.removeAttribute('aria-hidden');
    return;
  }
  // Último recurso: usar alert nativo preservado (sin recursión)
  if (__nativeAlert) { __nativeAlert(String(msg)); }
  else { try { console.error(String(msg)); } catch(e) {} }
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
  let procesoActual = null; // para completar

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
      const merma = (p.cantidad_resultante != null)
        ? Math.max(0, Number(p.cantidad_origen || 0) - Number(p.cantidad_resultante || 0))
        : 0;
      card.innerHTML = `
        <div class="title">${escapeHtml(p.insumo_origen)} → ${escapeHtml(p.insumo_destino)}</div>
        <div class="meta"><span>${escapeHtml(p.cantidad_origen)} ${escapeHtml(p.unidad_origen || '')}</span> <span>#${p.id}</span></div>
        <div class="badges">
          ${p.entrada_insumo_id ? `<span>Entrada #${p.entrada_insumo_id}</span>` : ''}
          ${p.mov_salida_id ? `<span>Salida #${p.mov_salida_id}</span>` : ''}
          ${merma > 0 ? `<span class="badge badge-warning">Merma: ${merma.toFixed(2)} ${escapeHtml(p.unidad_origen || '')}</span>` : ''}
        </div>
        ${p.qr_path ? `<button class="btn-qr" data-src="${escapeHtml(p.qr_path)}">QR</button>` : ''}
        ${p.estado === 'listo' && !p.entrada_insumo_id ? `<button class="btn-completar " data-id="${p.id}">Completar proceso</button>` : ''}
        ${p.estado === 'entregado' && p.merma_qr ? `<button class="btn-qr-merma" data-src="${escapeHtml(p.merma_qr)}">QR Merma</button>` : ''}
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
      const btnQrMerma = card.querySelector('.btn-qr-merma');
      if (btnQrMerma){
        btnQrMerma.addEventListener('click', () => {
          const src = btnQrMerma.getAttribute('data-src');
          if (src) window.open('../../' + src.replace(/^\/+/, ''), '_blank');
        });
      }
      const btnCompletar = card.querySelector('.btn-completar');
      if (btnCompletar){
        btnCompletar.addEventListener('click', () => {
          procesoActual = p;
          ensureCompletarModal(p);
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
        // Preparar modal estándar para completar
        procesoActual = cache.find(x => x.id === id) || {
          id, insumo_origen: '', insumo_destino: '', cantidad_origen: 0, unidad_origen: ''
        };
        ensureCompletarModal(procesoActual);
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
      const motivo = (qs('#cmpMotivo')?.value || '').trim();
      if (motivo) fd.append('motivo_merma', motivo);
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

  // Modal completar proceso (Bootstrap-like)
  function ensureCompletarModal(p){
    let modal = qs('#modalCompletarProc');
    if (!modal){
      // crear estructura si no existe (coincide con estilos bootstrap)
      const html = `
      <div class="modal fade" id="modalCompletarProc" tabindex="-1" role="dialog" aria-hidden="true">
        <div class="modal-dialog" role="document">
          <div style="color:black" class="modal-content">
            <div class="modal-header">
              <h5 style="color:black" class="modal-title">Completar proceso</h5>
              <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body">
              <div class="form-group">
                <label>Origen → Destino</label>
                <div id="cmpResumen"></div>
              </div>
              <div class="form-group">
                <label for="cmpCantidadRes">Cantidad resultante</label>
                <input id="cmpCantidadRes" type="number" step="0.01" min="0.01" class="form-control" placeholder="0.00">
              </div>
              <div class="form-group">
                <div id="cmpMermaBox" style="display:none">
                  <strong>Merma:</strong> <span id="cmpMermaQty">0</span>
                </div>
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
      const wrap = document.createElement('div');
      wrap.innerHTML = html;
      document.body.appendChild(wrap.firstElementChild);
      modal = qs('#modalCompletarProc');
      // Cerrar por botón X
      modal.querySelector('.close')?.addEventListener('click', ()=> hideModal(modal));
      modal.querySelector('.btn-secondary')?.addEventListener('click', ()=> hideModal(modal));
    }
    // Poblar
    const resumen = qs('#cmpResumen');
    const inp = qs('#cmpCantidadRes');
    const mermaBox = qs('#cmpMermaBox');
    const mermaQty = qs('#cmpMermaQty');
    if (resumen) resumen.textContent = `${p.insumo_origen} (${p.cantidad_origen} ${p.unidad_origen||''}) → ${p.insumo_destino}`;
    if (inp){
      inp.value = '';
      inp.oninput = () => {
        const val = parseFloat(inp.value || '0') || 0;
        const m = Math.max(0, (parseFloat(p.cantidad_origen)||0) - val);
        if (m > 0){ mermaBox.style.display = ''; mermaQty.textContent = m.toFixed(2) + ' ' + (p.unidad_origen||''); }
        else { mermaBox.style.display = 'none'; mermaQty.textContent = '0'; }
      };
    }
    const btn = qs('#cmpBtnConfirm');
    if (btn){
      btn.onclick = async ()=>{
        const val = parseFloat(inp.value || '0');
        if (!(val > 0)) { alert('Capture una cantidad válida'); return; }
        const comp = await apiComplete(p.id, val);
        if (!comp) return;
        hideModal(modal);
        // Actualizar cache y re-render
        const idx = cache.findIndex(x => x.id === p.id);
        if (idx >= 0){
          cache[idx].estado = 'listo';
          cache[idx].entrada_insumo_id = comp.entrada_insumo_id;
          cache[idx].mov_salida_id = comp.mov_salida_id;
          cache[idx].qr_path = comp.qr_path;
          cache[idx].cantidad_resultante = val;
          if (typeof comp.merma !== 'undefined') cache[idx].merma = comp.merma;
          if (comp.merma_qr) cache[idx].merma_qr = comp.merma_qr;
        }
        render(cache);
      };
    }
    showModal(modal);
  }

  // Helpers para mostrar/ocultar modal con o sin Bootstrap
  function showModal(selOrEl){
    const el = typeof selOrEl === 'string' ? qs(selOrEl) : selOrEl;
    if (!el) return;
    if (window.$ && $.fn && $.fn.modal) { $(el).modal('show'); return; }
    el.classList.add('show');
    el.style.display = 'block';
    el.removeAttribute('aria-hidden');
  }
  function hideModal(selOrEl){
    const el = typeof selOrEl === 'string' ? qs(selOrEl) : selOrEl;
    if (!el) return;
    if (window.$ && $.fn && $.fn.modal) { $(el).modal('hide'); return; }
    el.classList.remove('show');
    el.style.display = 'none';
    el.setAttribute('aria-hidden', 'true');
  }
})();
