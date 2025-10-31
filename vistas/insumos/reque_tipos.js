async function apiListar() {
  const r = await fetch('../../api/insumos/reque_tipos.php?accion=listar', { cache: 'no-store' });
  const j = await r.json();
  return j.resultado || j.rows || [];
}

async function apiCrear(nombre, activo) {
  const fd = new URLSearchParams({ accion: 'crear', nombre: nombre, activo: String(activo ? 1 : 0) });
  const r = await fetch('../../api/insumos/reque_tipos.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: fd });
  return r.json();
}

async function apiActualizar(id, nombre, activo) {
  const fd = new URLSearchParams({ accion: 'actualizar', id: String(id), nombre: nombre, activo: String(activo ? 1 : 0) });
  const r = await fetch('../../api/insumos/reque_tipos.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: fd });
  return r.json();
}

async function apiEliminar(id) {
  const fd = new URLSearchParams({ accion: 'eliminar', id: String(id) });
  const r = await fetch('../../api/insumos/reque_tipos.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: fd });
  return r.json();
}

function renderTabla(rows) {
  const tbody = document.querySelector('#tablaRequeTipos tbody');
  const filtro = (document.getElementById('filtro')?.value || '').toLowerCase();
  const filtrados = rows.filter(r => String(r.nombre||'').toLowerCase().includes(filtro));
  tbody.innerHTML = '';
  if (filtrados.length === 0) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4; td.textContent = 'Sin datos';
    tr.appendChild(td); tbody.appendChild(tr); return;
  }
  filtrados.forEach(r => {
    const tr = document.createElement('tr');
    const activoTxt = (parseInt(r.activo,10)===1) ? 'Sí' : 'No';
    tr.innerHTML = `
      <td>${r.id}</td>
      <td>${r.nombre}</td>
      <td>${activoTxt}</td>
      <td>
        <button type="button" class="btn custom-btn-sm btn-editar" data-id="${r.id}">Editar</button>
        <button type="button" class="btn btn-secondary btn-toggle" data-id="${r.id}" data-activo="${r.activo}">${parseInt(r.activo,10)===1?'Desactivar':'Activar'}</button>
      </td>
    `;
    tbody.appendChild(tr);
  });
  // bind acciones
  tbody.querySelectorAll('.btn-editar').forEach(b => b.addEventListener('click', (ev) => {
    const id = parseInt(ev.currentTarget.getAttribute('data-id'), 10);
    const item = rows.find(x => parseInt(x.id,10)===id);
    if (!item) return;
    document.getElementById('rt_id').value = String(item.id);
    document.getElementById('rt_nombre').value = item.nombre || '';
    document.getElementById('rt_activo').checked = parseInt(item.activo,10)===1;
  }));
  tbody.querySelectorAll('.btn-toggle').forEach(b => b.addEventListener('click', async (ev) => {
    const id = parseInt(ev.currentTarget.getAttribute('data-id'), 10);
    const activo = parseInt(ev.currentTarget.getAttribute('data-activo'), 10);
    const item = rows.find(x => parseInt(x.id,10)===id);
    if (!item) return;
    const nuevo = activo===1 ? 0 : 1;
    try {
      const jr = await apiActualizar(id, item.nombre, nuevo);
      if (!jr || jr.success === false) { alert(jr?.mensaje || 'No se pudo actualizar'); return; }
      cargar();
    } catch (e) { console.error(e); alert('Error al actualizar'); }
  }));
}

async function cargar() {
  const estado = document.getElementById('estado');
  try {
    const rows = await apiListar();
    window.__reque_tipos_cache = rows;
    renderTabla(rows);
    if (estado) estado.textContent = '';
  } catch (e) {
    console.error(e);
    if (estado) estado.textContent = 'Error al cargar';
  }
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('filtro')?.addEventListener('input', () => renderTabla(window.__reque_tipos_cache || []));
  document.getElementById('btnNuevo')?.addEventListener('click', () => {
    document.getElementById('rt_id').value = '';
    document.getElementById('rt_nombre').value = '';
    document.getElementById('rt_activo').checked = true;
    document.getElementById('rt_nombre').focus();
  });
  document.getElementById('formRequeTipo')?.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const id = parseInt(document.getElementById('rt_id').value || '0', 10);
    const nombre = (document.getElementById('rt_nombre').value || '').trim();
    const activo = document.getElementById('rt_activo').checked;
    if (!nombre) { alert('Nombre requerido'); return; }
    try {
      let jr;
      if (id > 0) jr = await apiActualizar(id, nombre, activo);
      else jr = await apiCrear(nombre, activo);
      if (!jr || jr.success === false) { alert(jr?.mensaje || 'No se pudo guardar'); return; }
      await cargar();
      // limpiar form si fue crear
      if (id === 0) {
        document.getElementById('rt_id').value = '';
        document.getElementById('rt_nombre').value = '';
        document.getElementById('rt_activo').checked = true;
      }
    } catch (e) { console.error(e); alert('Error al guardar'); }
  });
  document.getElementById('btnEliminar')?.addEventListener('click', async () => {
    const id = parseInt(document.getElementById('rt_id').value || '0', 10);
    if (!(id > 0)) { alert('Seleccione un registro'); return; }
    if (!confirm('¿Eliminar este registro?')) return;
    try {
      const jr = await apiEliminar(id);
      if (!jr || jr.success === false) { alert(jr?.mensaje || 'No se pudo eliminar'); return; }
      await cargar();
      document.getElementById('rt_id').value = '';
      document.getElementById('rt_nombre').value = '';
      document.getElementById('rt_activo').checked = true;
    } catch (e) { console.error(e); alert('Error al eliminar'); }
  });
  cargar();
});

