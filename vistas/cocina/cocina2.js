function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;
// Constante de envío en UI cocina
window.ENVIO_CASA_PRODUCT_ID = window.ENVIO_CASA_PRODUCT_ID || 9001;
window.CARGO_PLATAFORMA_PRODUCT_ID = window.CARGO_PLATAFORMA_PRODUCT_ID || 9000;
window.ultimoDetalleCocina = parseInt(localStorage.getItem('ultimoDetalleCocina') || '0', 10);
(() => {
  const qs = s => document.querySelector(s);
  const qsa = s => Array.from(document.querySelectorAll(s));

  const cols = {
    pendiente: qs('#col-pendiente'),
    en_preparacion: qs('#col-preparacion'),
    listo: qs('#col-listo'),
    entregado: qs('#col-entregado')
  };

  const rolUsuario = document.querySelector('#user-info')?.dataset.rol || '';

  const filtroInput = qs('#txtFiltro');
  const tipoEntregaSel = qs('#selTipoEntrega');
  const btnRefrescar = qs('#btnRefrescar');

  let cache = [];

  const allowedNext = {
    pendiente: 'en_preparacion',
    en_preparacion: 'listo',
    listo: 'entregado'
  };

  const style = document.createElement('style');
  style.textContent = `
    .kanban-item{position:relative;padding-bottom:30px;}
    .kanban-item .btn-ver{position:absolute;bottom:5px;right:5px;}
    #productoModalOverlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;z-index:1000;}
    #productoModalOverlay .modal-box{background:rgba(46, 31, 31, 0.5);padding:20px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,.3);max-width:400px;width:90%;max-height:90%;overflow:auto;position:relative;}
    #productoModalOverlay .close-btn{position:absolute;top:10px;right:10px;background:none;border:none;cursor:pointer;font-size:14px;}
    #productoModalOverlay .modal-box p{margin:4px 0;}
  `;
  document.head.appendChild(style);

  function render(items){
    const PID_ENVIO = Number(window.ENVIO_CASA_PRODUCT_ID || 9001);
    const PID_CARGO = Number(window.CARGO_PLATAFORMA_PRODUCT_ID || 9000);
    Object.values(cols).forEach(c => c.innerHTML = '');
    const txt = (filtroInput.value || '').toLowerCase();
    const tipo = (tipoEntregaSel.value || '').toLowerCase();

    const visibles = (items || []).filter(it => {
      const pid = Number(it.producto_id);
      return pid !== PID_ENVIO && pid !== PID_CARGO;
    });
    visibles.forEach(it => {
      const cat = (it.categoria || '').toLowerCase();
      if (rolUsuario === 'barra' && cat !== 'bebida') return;
      if (rolUsuario === 'alimentos' && cat === 'bebida') return;
      if (txt){
        const hay = (it.producto + ' ' + it.destino).toLowerCase().includes(txt);
        if (!hay) return;
      }
      if (tipo && it.tipo !== tipo) return;

      const card = document.createElement('div');
      card.className = 'kanban-item';
      card.draggable = true;
      card.dataset.id = it.detalle_id;
      card.dataset.estado = it.estado;
      card.dataset.productoId = it.producto_id;
      card.innerHTML = `
        <div class='title'>${it.producto} <small>x${it.cantidad}</small></div>
        <div class='meta'>
          <span>${it.destino}</span>
          <span>${formatHora(it.estado === 'entregado' ? it.entregado_hr : it.hora)}</span>
          ${it.observaciones ? `<span>Obs: ${escapeHtml(it.observaciones)}</span>` : ''}
        </div>
        <button class="btn-ver">Ver</button>
      `;
      const verBtn = card.querySelector('.btn-ver');
      verBtn.addEventListener('click', ev => { ev.stopPropagation(); mostrarModalProducto(it); });
      bindDrag(card);
      (cols[it.estado] || cols.pendiente).appendChild(card);
    });
  }

  function formatHora(s){
    try { return new Date(s.replace(' ', 'T')).toLocaleTimeString(); } catch(e){ return s; }
  }
  function escapeHtml(s){
    const div = document.createElement('div');
    div.innerText = s;
    return div.innerHTML;
  }

  function bindDrag(el){
    el.addEventListener('dragstart', ev => {
      ev.dataTransfer.setData('text/plain', el.dataset.id);
      setTimeout(()=> el.classList.add('dragging'), 0);
    });
    el.addEventListener('dragend', ()=> el.classList.remove('dragging'));
  }

  function mostrarModalProducto(item){
    const overlay = document.createElement('div');
    overlay.id = 'productoModalOverlay';
    const campos = [
      ['Producto','producto'],
      ['Categoría','categoria'],
      ['Cantidad','cantidad'],
      ['Precio unitario','precio_unitario'],
      ['Subtotal','subtotal'],
      ['Estado','estado'],
      ['Hora de creación','hora'],
      ['Hora de entrega','entregado_hr'],
      ['Minutos transcurridos','minutos_transcurridos'],
      ['Mesero','mesero'],
      ['Cajero','cajero'],
      ['Sede','sede'],
      ['Estado de entrega','estado_entrega'],
      ['Observaciones','observaciones'],
      ['Observaciones venta','observaciones_venta'],
      ['Insumos requeridos','insumos_requeridos'],
      ['Prioridad','prioridad']
    ];
    const contenido = campos.map(([lab, key]) => `<p><strong>${lab}:</strong> ${escapeHtml(item[key] != null ? String(item[key]) : '')}</p>`).join('');
    overlay.innerHTML = `<div class="modal-box"><button class="close-btn">Cerrar</button>${contenido}</div>`;
    document.body.appendChild(overlay);
    overlay.querySelector('.close-btn').addEventListener('click', () => overlay.remove());
  }

  qsa('.kanban-dropzone').forEach(zone => {
    zone.addEventListener('dragover', ev => { ev.preventDefault(); zone.classList.add('drag-over'); });
    zone.addEventListener('dragleave', ()=> zone.classList.remove('drag-over'));
    zone.addEventListener('drop', async ev => {
      ev.preventDefault();
      zone.classList.remove('drag-over');
      const id = ev.dataTransfer.getData('text/plain');
      const card = document.querySelector(`.kanban-item[data-id='${id}']`);
      if (!card) return;
      const PID_ENVIO = Number(window.ENVIO_CASA_PRODUCT_ID || 9001);
      if (Number(card.dataset.productoId || 0) === PID_ENVIO) {
        return; // no-op sobre envío
      }
      const current = card.dataset.estado;
      const nuevoEstado = zone.closest('.kanban-board').dataset.status;
      if (allowedNext[current] !== nuevoEstado){
        alert('Transición no permitida');
        return;
      }
      const ok = await cambiarEstado(+id, nuevoEstado);
      if (ok){
        card.dataset.estado = nuevoEstado;
        zone.appendChild(card);
        const idx = cache.findIndex(x => x.detalle_id === +id);
        if (idx >= 0) cache[idx].estado = nuevoEstado;
      }
    });
  });

  async function cargar(){
    const res = await fetch(`../../api/cocina/listar_productos_cocina.php`);
    if (!res.ok){ alert('Error al cargar comandas'); return; }
    const json = await res.json();
    if (!json.success){ alert(json.message || 'Error'); return; }
    cache = json.resultado || json.data || json;
    render(cache);
    const ids = cache.map(it => parseInt(it.detalle_id, 10) || 0);
    if (ids.length) {
      window.ultimoDetalleCocina = Math.max.apply(null, ids);
      localStorage.setItem('ultimoDetalleCocina', String(window.ultimoDetalleCocina));
    }
  }

  async function cambiarEstado(detalle_id, nuevo_estado){
    try{
      const res = await fetch(`../../api/cocina/cambiar_estado_producto.php`, {
        method:'POST',
        headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify({ detalle_id, nuevo_estado })
      });
      const data = await res.json();
      if (!res.ok || data.success === false){
        alert(data.message || 'No se pudo cambiar el estado');
        return false;
      }
      return true;
    }catch(e){
      alert('Error de red');
      return false;
    }
  }

  window.cargarDatosCocina = cargar;

  filtroInput.addEventListener('input', ()=> render(cache));
  tipoEntregaSel.addEventListener('change', ()=> render(cache));
  btnRefrescar.addEventListener('click', cargar);
})();

function escucharNuevasVentas(ultimoId) {
  $.ajax({
    url: '../../api/cocina/listen_updates.php',
    type: 'POST',
    data: { ultimo_id: ultimoId },
    dataType: 'json',
    timeout: 30000,
    success: function (resp) {
      if (resp.nueva_venta) {
        cargarDatosCocina();
      }
      const nextId = resp.ultimo_id || ultimoId;
      window.ultimoDetalleCocina = nextId;
      localStorage.setItem('ultimoDetalleCocina', String(nextId));
      escucharNuevasVentas(nextId);
    },
    error: function () {
      setTimeout(() => escucharNuevasVentas(ultimoId), 1000);
    }
  });
}

$(document).ready(function () {
  if (typeof cargarDatosCocina === 'function') {
    cargarDatosCocina().then(() => {
      const startId = window.ultimoDetalleCocina || 0;
      escucharNuevasVentas(startId);
    });
  } else {
    escucharNuevasVentas(0);
  }
});
