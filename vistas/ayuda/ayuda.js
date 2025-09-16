function showAppMsg(msg) {
  const body = document.querySelector('#appMsgModal .modal-body');
  if (body) body.textContent = String(msg);
  showModal('#appMsgModal');
}
window.alert = showAppMsg;

const itemsPorPaginaAyuda = 10;
let seccionesAyuda = [
  { titulo: 'Ventas', contenido: 'Cómo registrar ventas, aplicar descuentos y cerrar corte.' },
  { titulo: 'Cortes de caja', contenido: 'Apertura de caja, fondo inicial, cortes temporales y finales.' },
  { titulo: 'Inventario', contenido: 'Altas, edición de existencias y eliminación de productos.' },
  { titulo: 'Repartos', contenido: 'Marcar en camino, confirmar entrega y evidencia de entrega.' },
  { titulo: 'Meseros y mesas', contenido: 'Asignar mesas a meseros y gestión por usuario.' },
  { titulo: 'Insumos', contenido: 'Registro de entradas y control por receta.' },
  { titulo: 'Reportes', contenido: 'Reportería dinámica por vistas/tablas y filtros.' },
  { titulo: 'Horarios', contenido: 'Configurar series y horarios de cobro.' },
  { titulo: 'Usuarios', contenido: 'Altas/bajas, permisos y roles.' },
  { titulo: 'Rutas', contenido: 'Administración de rutas y permisos del sistema.' }
];
let filtroAyuda = '';
let paginaAyuda = 1;

function renderAyuda() {
  const cont = document.getElementById('contenedorAyuda');
  const pag = document.getElementById('paginadorAyuda');
  if (!cont || !pag) return;
  const filtradas = seccionesAyuda.filter(s => (s.titulo + ' ' + s.contenido).toLowerCase().includes(filtroAyuda));
  const totalPag = Math.max(1, Math.ceil(filtradas.length / itemsPorPaginaAyuda));
  paginaAyuda = Math.min(Math.max(1, paginaAyuda), totalPag);
  const ini = (paginaAyuda - 1) * itemsPorPaginaAyuda;
  const fin = ini + itemsPorPaginaAyuda;
  const visibles = filtradas.slice(ini, fin);

  cont.innerHTML = visibles.map(s => `
    <div class="product-view" style="margin-bottom:10px;">
      <div class="product-name">${s.titulo}</div>
      <div>${s.contenido}</div>
    </div>`).join('');

  // Paginador
  pag.innerHTML = '';
  const prevLi = document.createElement('li');
  prevLi.className = 'page-item' + (paginaAyuda === 1 ? ' disabled' : '');
  const prevA = document.createElement('a');
  prevA.href = '#'; prevA.className = 'page-link'; prevA.textContent = 'Anterior';
  prevA.addEventListener('click', e => { e.preventDefault(); if (paginaAyuda > 1) { paginaAyuda--; renderAyuda(); } });
  prevLi.appendChild(prevA); pag.appendChild(prevLi);
  for (let i = 1; i <= totalPag; i++) {
    const li = document.createElement('li');
    li.className = 'page-item' + (i === paginaAyuda ? ' active' : '');
    const a = document.createElement('a'); a.href = '#'; a.className = 'page-link'; a.textContent = String(i);
    a.addEventListener('click', e => { e.preventDefault(); paginaAyuda = i; renderAyuda(); });
    li.appendChild(a); pag.appendChild(li);
  }
  const nextLi = document.createElement('li');
  nextLi.className = 'page-item' + (paginaAyuda === totalPag ? ' disabled' : '');
  const nextA = document.createElement('a');
  nextA.href = '#'; nextA.className = 'page-link'; nextA.textContent = 'Siguiente';
  nextA.addEventListener('click', e => { e.preventDefault(); if (paginaAyuda < totalPag) { paginaAyuda++; renderAyuda(); } });
  nextLi.appendChild(nextA); pag.appendChild(nextLi);
}

document.addEventListener('DOMContentLoaded', () => {
  const buscar = document.getElementById('buscarAyuda');
  if (buscar) {
    let t; buscar.addEventListener('input', e => { clearTimeout(t); t = setTimeout(() => { filtroAyuda = (e.target.value || '').toLowerCase(); paginaAyuda = 1; renderAyuda(); }, 250); });
  }
  renderAyuda();
});

