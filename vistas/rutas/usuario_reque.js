function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;

async function cargarUsuarios() {
    try {
        const resp = await fetch('../../api/usuarios/listar_usuarios.php');
        const data = await resp.json();
        const sel = document.getElementById('usuarioSelect');
        sel.innerHTML = '';
        if (data.success) {
            (data.usuarios || []).forEach(u => {
                const opt = document.createElement('option');
                opt.value = u.nombre;
                opt.textContent = u.nombre;
                sel.appendChild(opt);
            });
            if (sel.value) cargarRequeUsuario(sel.value);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar usuarios');
    }
}

document.getElementById('usuarioSelect').onchange = ev => {
    const usuario = ev.target.value;
    cargarRequeUsuario(usuario);
};

async function cargarRequeUsuario(usuario) {
    if (!usuario) return;
    try {
        const resp = await fetch(`../../api/insumos/listar_usuario_reque.php?usuario=${encodeURIComponent(usuario)}`);
        const data = await resp.json();
        const tbody = document.querySelector('#tablaRequeUsuario tbody');
        tbody.innerHTML = '';
        if (data.success) {
            (data.resultado || []).forEach(r => {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td>${r.nombre}</td>`;
                const tdCheck = document.createElement('td');
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = !!r.asignado;
                chk.dataset.id = r.id;
                tdCheck.appendChild(chk);
                tr.appendChild(tdCheck);
                tbody.appendChild(tr);
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar áreas/reque');
    }
}

async function guardarRequeUsuario() {
    const usuario = document.getElementById('usuarioSelect').value;
    if (!usuario) return;
    const checks = document.querySelectorAll('#tablaRequeUsuario tbody input[type="checkbox"]');
    const reques = Array.from(checks).filter(c => c.checked).map(c => parseInt(c.dataset.id, 10));
    try {
        const resp = await fetch('../../api/insumos/guardar_usuario_reque.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usuario, reques })
        });
        const data = await resp.json();
        alert(data.mensaje);
        if (data.success) cargarRequeUsuario(usuario);
    } catch (err) {
        console.error(err);
        alert('Error al guardar áreas/reque');
    }
}

document.getElementById('btnGuardar').onclick = guardarRequeUsuario;

window.addEventListener('DOMContentLoaded', cargarUsuarios);

