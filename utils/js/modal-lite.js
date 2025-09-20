/*!
 * modal-lite.js — Compat modal manager (ES5-friendly)
 * - Single backdrop, stacked modals, data-attrs, ESC/backdrop close
 * - Fires: 'modal:shown'/'modal:hidden' and 'shown.bs.modal'/'hidden.bs.modal'
 * - jQuery bridge: $(el).modal('show'|'hide'|'toggle')
 * - Idempotent: ignore if already installed
 */
(function (win, doc) {
  'use strict';
  if (win.ModalLite && win.ModalLite.__installed) return;

  var BASE_Z_MODAL = 1050;
  var BASE_Z_BACKDROP = 1040;
  var STACK_STEP = 20;
  var TRANSITION_FALLBACK_MS = 250;

  var stack = []; // array de elementos .modal en orden de apertura (base -> top)
  var installed = false;

  function q(sel, ctx) { return (ctx || doc).querySelector(sel); }
  function qa(sel, ctx) { return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel)); }

  function hasClass(el, cls) { return el && (' ' + el.className + ' ').indexOf(' ' + cls + ' ') > -1; }
  function addClass(el, cls) { if (!hasClass(el, cls)) el.className += (el.className ? ' ' : '') + cls; }
  function removeClass(el, cls) {
    if (!el) return;
    el.className = (' ' + el.className + ' ').replace(' ' + cls + ' ', ' ').trim();
  }

  function removeAllBackdrops() {
    qa('.modal-backdrop').forEach(function (bd) {
      removeClass(bd, 'show');
      if (bd.parentNode) bd.parentNode.removeChild(bd);
    });
  }

  function lockBody()   { addClass(doc.body, 'modal-open'); }
  function unlockBody() { removeClass(doc.body, 'modal-open'); }

  function ensureBackdrop() {
    var bd = q('.modal-backdrop[data-mlite="1"]');
    if (!bd) {
      bd = doc.createElement('div');
      bd.className = 'modal-backdrop fade';
      bd.setAttribute('data-mlite', '1');
      doc.body.appendChild(bd);
      // for fade-in
      setTimeout(function(){ addClass(bd, 'show'); }, 0);

      // Click fuera → cerrar top si no es static
      bd.addEventListener('click', function () {
        var top = stack.length ? stack[stack.length - 1] : null;
        if (!top) return;
        var isStatic = (top.getAttribute('data-backdrop') === 'static');
        if (!isStatic) hideModal('#' + top.id);
      });
    }
    // z-index acorde al stack
    var z = BASE_Z_BACKDROP + (stack.length ? (stack.length - 1) * STACK_STEP : 0);
    bd.style.zIndex = String(z);
    return bd;
  }

  function normalizeStructure(modal) {
    var dialog = q('.modal-dialog', modal);
    if (!dialog) {
      dialog = doc.createElement('div');
      dialog.className = 'modal-dialog';
      var content = doc.createElement('div');
      content.className = 'modal-content';
      while (modal.firstChild) content.appendChild(modal.firstChild);
      dialog.appendChild(content);
      modal.appendChild(dialog);
    } else if (!q('.modal-content', dialog)) {
      var content2 = doc.createElement('div');
      content2.className = 'modal-content';
      while (dialog.firstChild) content2.appendChild(dialog.firstChild);
      dialog.appendChild(content2);
    }
  }

  function forceReflow(el) { return el && el.offsetWidth; }

  function dispatchAll(modal, nameNative, nameBs) {
    try {
      modal.dispatchEvent(new CustomEvent(nameNative));
    } catch (e) {
      // IE fallback: omit
    }
    // Bootstrap-like (nativo)
    try {
      modal.dispatchEvent(new CustomEvent(nameBs));
    } catch (e2) {}
    // jQuery bridge
    if (win.jQuery) {
      try { win.jQuery(modal).trigger(nameBs); } catch(e3){}
    }
  }

  function setZIndexFor(modal, idx) {
    var z = BASE_Z_MODAL + idx * STACK_STEP;
    modal.style.zIndex = String(z);
    var bd = ensureBackdrop();
    bd.style.zIndex = String(z - 10); // siempre por debajo del modal top
  }

  function topIndexOf(modal) {
    for (var i = 0; i < stack.length; i++) {
      if (stack[i] === modal) return i;
    }
    return -1;
  }

  function showModal(selector) {
    var modal = (typeof selector === 'string') ? q(selector) : selector;
    if (!modal) return;

    // Si ya está visible, solo enfocar
    if (hasClass(modal, 'show')) {
      tryFocus(modal);
      return;
    }

    normalizeStructure(modal);
    ensureBackdrop();
    lockBody();

    // apilar
    stack.push(modal);
    setZIndexFor(modal, stack.length - 1);

    modal.style.display = 'block';
    modal.removeAttribute('aria-hidden');

    // activar transición
    forceReflow(modal);
    addClass(modal, 'show');

    dispatchAll(modal, 'modal:shown', 'shown.bs.modal');
    tryFocus(modal);
  }

  function finishHide(modal) {
    modal.style.display = 'none';
    modal.setAttribute('aria-hidden', 'true');
    dispatchAll(modal, 'modal:hidden', 'hidden.bs.modal');

    // quitar del stack si quedara por ahí
    var idx = topIndexOf(modal);
    if (idx > -1) stack.splice(idx, 1);

    if (!stack.length) {
      removeAllBackdrops();
      unlockBody();
    } else {
      // recalcular z-index para el nuevo top
      var newTop = stack[stack.length - 1];
      setZIndexFor(newTop, stack.length - 1);
    }
  }

  function hideModal(selector) {
    var modal = (typeof selector === 'string') ? q(selector) : selector;
    if (!modal) return;
    if (!hasClass(modal, 'show')) return finishHide(modal);

    removeClass(modal, 'show');

    // Esperar fin de transición si tiene .fade
    if (hasClass(modal, 'fade')) {
      var done = false;
      var onEnd = function () {
        if (done) return;
        done = true;
        modal.removeEventListener('transitionend', onEnd);
        finishHide(modal);
      };
      modal.addEventListener('transitionend', onEnd);
      setTimeout(onEnd, TRANSITION_FALLBACK_MS);
    } else {
      finishHide(modal);
    }
  }

  function toggleModal(selector) {
    var modal = (typeof selector === 'string') ? q(selector) : selector;
    if (!modal) return;
    if (hasClass(modal, 'show')) hideModal(modal);
    else showModal(modal);
  }

  function tryFocus(modal) {
    // Intento simple: primer elemento interactivo o botón de cerrar
    var focusable = modal.querySelector('[data-dismiss="modal"], button, [href], input, select, textarea');
    if (focusable && focusable.focus) {
      try { focusable.focus(); } catch (e) {}
    }
  }

  // Delegación global de clicks
  function onDocClick(e) {
    // Abrir
    var open = closest(e.target, '[data-toggle="modal"]');
    if (open) {
      var target = open.getAttribute('data-target') || open.dataset.target;
      if (target) {
        e.preventDefault();
        showModal(target);
        return;
      }
    }
    // Cerrar
    var dismiss = closest(e.target, '[data-dismiss="modal"]');
    if (dismiss) {
      var modal = closest(e.target, '.modal');
      if (modal) {
        e.preventDefault();
        hideModal('#' + modal.id);
      }
    }
  }

  function onDocKeydown(e) {
    if (e.key === 'Escape' || e.keyCode === 27) {
      if (!stack.length) return;
      var top = stack[stack.length - 1];
      var allowKeyboard = top.getAttribute('data-keyboard');
      if (allowKeyboard === 'false') return; // respeta data-keyboard="false"
      hideModal('#' + top.id);
    }
  }

  function closest(el, sel) {
    while (el && el.nodeType === 1) {
      if (matches(el, sel)) return el;
      el = el.parentNode;
    }
    return null;
  }
  function matches(el, sel) {
    var p = Element.prototype;
    var f = p.matches || p.matchesSelector || p.msMatchesSelector || p.webkitMatchesSelector;
    return f.call(el, sel);
  }

  // Limpieza defensiva al cargar: quita backdrops huérfanos
  function onDomReady() {
    if (!q('.modal.show')) {
      removeAllBackdrops();
      unlockBody();
    }
  }

  // jQuery bridge opcional
  function installJQueryBridge() {
    if (!win.jQuery || !win.jQuery.fn) return;
    var $ = win.jQuery;
    if ($.fn.modal && $.fn.modal.__mlite) return; // ya instalado

    $.fn.modal = function (action) {
      return this.each(function () {
        var sel = this.id ? ('#' + this.id) : this;
        if (action === 'show') showModal(sel);
        else if (action === 'hide') hideModal(sel);
        else if (action === 'toggle') toggleModal(sel);
        else {
          // Si pasan opciones tipo { backdrop:'static', keyboard:false }, solo setear data-attrs
          if (action && typeof action === 'object') {
            if (action.backdrop) this.setAttribute('data-backdrop', String(action.backdrop));
            if (typeof action.keyboard !== 'undefined') this.setAttribute('data-keyboard', String(!!action.keyboard));
          }
        }
      });
    };
    $.fn.modal.__mlite = true;
  }

  // Instalación
  function install() {
    if (installed) return;
    installed = true;

    doc.addEventListener('click', onDocClick);
    doc.addEventListener('keydown', onDocKeydown);
    if (doc.readyState === 'loading') {
      doc.addEventListener('DOMContentLoaded', onDomReady);
    } else {
      onDomReady();
    }
    installJQueryBridge();
  }

  // Exponer API pública
  win.showModal   = showModal;
  win.hideModal   = hideModal;
  win.toggleModal = toggleModal;
  win.ModalLite = {
    show: showModal,
    hide: hideModal,
    toggle: toggleModal,
    isOpen: function (el) {
      el = (typeof el === 'string') ? q(el) : el;
      return !!(el && hasClass(el, 'show'));
    },
    stackSize: function () { return stack.length; },
    version: '1.2.0',
    __installed: true
  };

  install();

})(window, document);
