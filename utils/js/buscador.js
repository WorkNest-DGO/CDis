function normalizarTexto(str) {
    return (str || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

function inicializarBuscadorDetalle() {
    const input = document.querySelector('#detalle_buscador');
    const select = document.querySelector('#detalle_producto');
    const lista = document.querySelector('#detalle_lista');
    if (!input || !lista || input.dataset.autocompleteInitialized) return;
    input.dataset.autocompleteInitialized = 'true';

    input.addEventListener('input', () => {
        const val = normalizarTexto(input.value.trim());
        lista.innerHTML = '';
        if (!val) {
            lista.style.display = 'none';
            return;
        }
        const arr = Array.isArray(window.catalogo) ? window.catalogo : [];
        arr.filter(p => normalizarTexto(p.nombre).includes(val))
            .slice(0, 50)
            .forEach(p => {
                const li = document.createElement('li');
                li.className = 'list-group-item list-group-item-action';
                li.textContent = p.nombre;
                li.addEventListener('click', () => {
                    input.value = p.nombre;
                    if (select) {
                        let opt = select.querySelector(`option[value="${p.id}"]`);
                        if (!opt) {
                            opt = document.createElement('option');
                            opt.value = p.id;
                            opt.dataset.precio = p.precio;
                            opt.dataset.existencia = p.existencia;
                            select.appendChild(opt);
                        }
                        select.value = p.id;
                        select.dispatchEvent(new Event('change'));
                    }
                    const prod = (window.catalogo || []).find(c => parseInt(c.id) === parseInt(p.id));
                    const cant = document.querySelector('#detalle_cantidad');
                    if (prod && prod.existencia && cant) {
                        cant.setAttribute('max', prod.existencia);
                    } else if (cant) {
                        cant.removeAttribute('max');
                    }
                    lista.innerHTML = '';
                    lista.style.display = 'none';
                });
                lista.appendChild(li);
            });
        lista.style.display = lista.children.length ? 'block' : 'none';
    });

    document.addEventListener('click', e => {
        const cont = input.closest('.selector-producto');
        if (!cont || !cont.contains(e.target)) {
            lista.style.display = 'none';
        }
    });
}
