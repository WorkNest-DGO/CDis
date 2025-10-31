async function listarProveedores() {
  try {
    const r = await fetch('../../api/insumos/listar_proveedores.php', { cache: 'no-store' });
    const j = await r.json();
    if (!j || !j.success) throw new Error(j?.mensaje || 'Error al listar proveedores');
    const sel = document.getElementById('selProveedor');
    sel.innerHTML = '<option value="">-- Nuevo proveedor --</option>';
    (j.resultado || []).forEach(p => {
      const opt = document.createElement('option');
      opt.value = p.id;
      opt.textContent = p.nombre;
      sel.appendChild(opt);
    });
  } catch (e) {
    console.error(e);
    alert('No se pudieron cargar proveedores');
  }
}

function limpiarFormulario() {
  document.getElementById('formProveedor').reset();
  document.getElementById('proveedorId').value = '';
  const activo = document.getElementById('activo');
  if (activo) activo.checked = true;
}

async function cargarProveedor(id) {
  if (!id) {
    limpiarFormulario();
    return;
  }
  try {
    const r = await fetch(`../../api/insumos/obtener_proveedor.php?id=${encodeURIComponent(id)}`, { cache: 'no-store' });
    const j = await r.json();
    if (!j || !j.success) throw new Error(j?.mensaje || 'Error al obtener proveedor');
    const p = j.resultado || {};
    document.getElementById('proveedorId').value = p.id || '';
    document.getElementById('nombre').value = p.nombre || '';
    document.getElementById('rfc').value = p.rfc || '';
    document.getElementById('razon_social').value = p.razon_social || '';
    document.getElementById('regimen_fiscal').value = p.regimen_fiscal || '';
    document.getElementById('correo_facturacion').value = p.correo_facturacion || '';
    document.getElementById('telefono').value = p.telefono || '';
    document.getElementById('telefono2').value = p.telefono2 || '';
    document.getElementById('correo').value = p.correo || '';
    document.getElementById('direccion').value = p.direccion || '';
    document.getElementById('contacto_nombre').value = p.contacto_nombre || '';
    document.getElementById('contacto_puesto').value = p.contacto_puesto || '';
    document.getElementById('dias_credito').value = Number.isFinite(+p.dias_credito) ? p.dias_credito : 0;
    document.getElementById('limite_credito').value = Number.isFinite(+p.limite_credito) ? (+p.limite_credito).toFixed(2) : '0.00';
    document.getElementById('banco').value = p.banco || '';
    document.getElementById('clabe').value = p.clabe || '';
    document.getElementById('cuenta_bancaria').value = p.cuenta_bancaria || '';
    document.getElementById('sitio_web').value = p.sitio_web || '';
    document.getElementById('observacion').value = p.observacion || '';
    const activo = document.getElementById('activo');
    if (activo) activo.checked = String(p.activo) === '1';
  } catch (e) {
    console.error(e);
    alert('No se pudo cargar el proveedor');
  }
}

function recolectarDatos() {
  const data = {
    nombre: document.getElementById('nombre').value.trim(),
    rfc: document.getElementById('rfc').value.trim() || null,
    razon_social: document.getElementById('razon_social').value.trim() || null,
    regimen_fiscal: document.getElementById('regimen_fiscal').value.trim() || null,
    correo_facturacion: document.getElementById('correo_facturacion').value.trim() || null,
    telefono: document.getElementById('telefono').value.trim() || null,
    telefono2: document.getElementById('telefono2').value.trim() || null,
    correo: document.getElementById('correo').value.trim() || null,
    direccion: document.getElementById('direccion').value.trim() || null,
    contacto_nombre: document.getElementById('contacto_nombre').value.trim() || null,
    contacto_puesto: document.getElementById('contacto_puesto').value.trim() || null,
    dias_credito: parseInt(document.getElementById('dias_credito').value || '0', 10) || 0,
    limite_credito: parseFloat(document.getElementById('limite_credito').value || '0') || 0,
    banco: document.getElementById('banco').value.trim() || null,
    clabe: document.getElementById('clabe').value.trim() || null,
    cuenta_bancaria: document.getElementById('cuenta_bancaria').value.trim() || null,
    sitio_web: document.getElementById('sitio_web').value.trim() || null,
    observacion: document.getElementById('observacion').value.trim() || null,
    activo: document.getElementById('activo').checked ? 1 : 0,
  };
  return data;
}

async function guardarProveedor(ev) {
  ev?.preventDefault?.();
  const id = parseInt(document.getElementById('proveedorId').value || '0', 10) || 0;
  const data = recolectarDatos();
  if (!data.nombre) {
    alert('El nombre es obligatorio');
    document.getElementById('nombre').focus();
    return;
  }
  try {
    const url = id > 0 ? '../../api/insumos/actualizar_proveedor.php' : '../../api/insumos/agregar_proveedor.php';
    const payload = id > 0 ? { id, ...data } : data;
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const j = await r.json();
    if (!j || !j.success) throw new Error(j?.mensaje || 'Error al guardar');
    alert('Guardado correctamente');
    await listarProveedores();
    if (id === 0) {
      // seleccionar el recién creado si es posible: recargar y buscar por nombre
      // no tenemos el ID retornado, la API actual no lo regresa; mantenemos en blanco
      document.getElementById('selProveedor').value = '';
      limpiarFormulario();
    }
  } catch (e) {
    console.error(e);
    alert(e.message || 'Error al guardar');
  }
}

async function eliminarProveedor() {
  const id = parseInt(document.getElementById('proveedorId').value || '0', 10) || 0;
  if (!id) {
    alert('Selecciona un proveedor para eliminar');
    return;
  }
  if (!confirm('¿Desactivar proveedor?')) return;
  try {
    const r = await fetch('../../api/insumos/eliminar_proveedor.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id })
    });
    const j = await r.json();
    if (!j || !j.success) throw new Error(j?.mensaje || 'Error al eliminar');
    alert('Proveedor desactivado');
    await listarProveedores();
    document.getElementById('selProveedor').value = '';
    limpiarFormulario();
  } catch (e) {
    console.error(e);
    alert(e.message || 'Error al eliminar');
  }
}

document.addEventListener('DOMContentLoaded', () => {
  listarProveedores().then(() => {
    // vacío por defecto
  });
  document.getElementById('selProveedor').addEventListener('change', (ev) => {
    const id = ev.target.value;
    cargarProveedor(id);
  });
  const btnNuevo = document.getElementById('btnNuevo');
  if (btnNuevo) {
    btnNuevo.addEventListener('click', () => {
      document.getElementById('selProveedor').value = '';
      limpiarFormulario();
      document.getElementById('nombre').focus();
    });
  }
  document.getElementById('formProveedor').addEventListener('submit', guardarProveedor);
  document.getElementById('btnEliminar').addEventListener('click', eliminarProveedor);
});
