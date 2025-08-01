let proveedores = [];
let insumosLista = [];

async function cargarProveedores() {
    try {
        const r = await fetch('../../api/insumos/listar_proveedores.php');
        const data = await r.json();
        if (data.success) {
            proveedores = data.resultado;
            const sel = document.getElementById('proveedor_id');
            sel.innerHTML = '<option value="">--Selecciona--</option>';
            proveedores.forEach(p => {
                const op = document.createElement('option');
                op.value = p.id;
                op.textContent = p.nombre;
                sel.appendChild(op);
            });
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar proveedores');
    }
}

async function cargarInsumos() {
    try {
        const r = await fetch('../../api/insumos/listar_insumos.php');
        const data = await r.json();
        if (data.success) {
            insumosLista = data.resultado;
            const sel = document.getElementById('insumo_id');
            sel.innerHTML = '<option value="">--Selecciona--</option>';
            insumosLista.forEach(i => {
                const op = document.createElement('option');
                op.value = i.id;
                op.textContent = i.nombre;
                sel.appendChild(op);
            });
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos');
    }
}

function calcularValorUnitario() {
    const cantidad = parseFloat(document.getElementById('cantidad').value) || 0;
    const total = parseFloat(document.getElementById('costo_total').value) || 0;
    const valor = cantidad > 0 ? total / cantidad : 0;
    document.getElementById('valor_unitario').value = valor.toFixed(2);
}

function validarCampos() {
    const proveedor = document.getElementById('proveedor_id').value;
    const insumo = document.getElementById('insumo_id').value;
    const cantidad = parseFloat(document.getElementById('cantidad').value);
    const total = parseFloat(document.getElementById('costo_total').value);
    if (!proveedor || !insumo) {
        alert('Selecciona proveedor e insumo');
        return false;
    }
    if (!cantidad || cantidad <= 0) {
        alert('Cantidad inválida');
        return false;
    }
    if (!total || total <= 0) {
        alert('Costo total inválido');
        return false;
    }
    return true;
}

async function enviarRegistro(ev) {
    ev.preventDefault();
    if (!validarCampos()) return;
    const payload = {
        proveedor_id: parseInt(document.getElementById('proveedor_id').value),
        insumo_id: parseInt(document.getElementById('insumo_id').value),
        cantidad: parseFloat(document.getElementById('cantidad').value),
        unidad: document.getElementById('unidad').value,
        costo_total: parseFloat(document.getElementById('costo_total').value),
        valor_unitario: parseFloat(document.getElementById('valor_unitario').value),
        descripcion: document.getElementById('descripcion').value,
        referencia_doc: document.getElementById('referencia_doc').value,
        folio_fiscal: document.getElementById('folio_fiscal').value
    };
    try {
        const r = await fetch('../../api/insumos/entradas_proveedor.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await r.json();
        if (data.success) {
            alert('Registrado');
            document.getElementById('formEntrada').reset();
            document.getElementById('valor_unitario').value = '';
            listarEntradas();
        } else {
            alert(data.mensaje || 'Error al registrar');
        }
    } catch (err) {
        console.error(err);
        alert('Error al registrar');
    }
}

async function listarEntradas() {
    try {
        const r = await fetch('../../api/insumos/entradas_proveedor.php');
        const data = await r.json();
        if (data.success) {
            const tbody = document.querySelector('#tablaHistorial tbody');
            tbody.innerHTML = '';
            data.resultado.forEach(e => {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td>${e.fecha}</td><td>${e.proveedor}</td><td>${e.insumo}</td><td>${e.cantidad}</td><td>${e.unidad}</td><td>${e.costo_total}</td>`;
                tbody.appendChild(tr);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    cargarProveedores();
    cargarInsumos();
    listarEntradas();
    document.getElementById('cantidad').addEventListener('input', calcularValorUnitario);
    document.getElementById('costo_total').addEventListener('input', calcularValorUnitario);
    document.getElementById('formEntrada').addEventListener('submit', enviarRegistro);
});
