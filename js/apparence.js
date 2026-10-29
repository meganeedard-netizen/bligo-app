// BliGO - thème clair / foncé (28/10/2026, comme l'appli Gaspiz).
// Chargé dans le <head> de chaque page usager, avant l'affichage : la classe
// "dark" est posée tout de suite, sans flash blanc à l'ouverture. Le choix se
// fait dans le profil et reste sur le téléphone.
(function () {
  var KEY = 'bligo_apparence';

  function apply(theme) {
    var dark = theme === 'fonce';
    document.documentElement.classList.toggle('dark', dark);
    // Heure et batterie en blanc sur fond foncé (appli iPhone/Android).
    var plugins = window.Capacitor && window.Capacitor.Plugins;
    if (plugins && plugins.StatusBar) {
      try { plugins.StatusBar.setStyle({ style: dark ? 'DARK' : 'LIGHT' }); } catch (e) { /* ancienne version de l'appli */ }
    }
    // Fond natif de l'écran, visible un instant entre deux pages : sans lui,
    // flash blanc en thème foncé sur un iPhone réglé en mode clair.
    if (plugins && plugins.BligoApparence) {
      try { plugins.BligoApparence.setTheme({ dark: dark }).catch(function () {}); } catch (e) { /* ancienne version de l'appli */ }
    }
  }

  function get() {
    try { return localStorage.getItem(KEY) === 'fonce' ? 'fonce' : 'clair'; } catch (e) { return 'clair'; }
  }

  window.bligoApparence = {
    get: get,
    set: function (theme) {
      try { localStorage.setItem(KEY, theme); } catch (e) { /* stockage indisponible : choix pour cette page seulement */ }
      apply(theme);
    },
  };

  apply(get());

  // Dans l'appli iPhone/Android (pas sur le site) : un appui long sur un texte
  // ou une image n'ouvre plus le menu Copier / Traduire / Partager du
  // téléphone, comme dans une vraie appli (28/10/2026). Les champs de saisie
  // restent sélectionnables.
  if (window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) {
    document.documentElement.classList.add('is-app');
    var style = document.createElement('style');
    style.textContent =
      'html.is-app, html.is-app body, html.is-app a, html.is-app img, html.is-app button { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }' +
      'html.is-app input, html.is-app textarea, html.is-app [contenteditable] { -webkit-user-select: text; user-select: text; -webkit-touch-callout: default; }';
    document.head.appendChild(style);

    // iOS affiche l'adresse d'un lien (« capacitor://localhost/profil.html »)
    // à l'appui long, même sans aperçu (29/10/2026). Dans l'appli, les liens
    // n'ont donc plus d'href : l'adresse passe dans data-app-href et un clic
    // y mène comme avant. Les téléchargements (download, blob:) sont laissés.
    var strip = function (a) {
      var href = a.getAttribute('href');
      if (href === null || a.hasAttribute('download') || /^(blob|data):/.test(href)) return;
      a.setAttribute('data-app-href', href);
      a.removeAttribute('href');
      if (!a.hasAttribute('role')) a.setAttribute('role', 'link');
    };
    var stripAll = function (root) {
      if (root.nodeType !== 1) return;
      if (root.tagName === 'A') strip(root);
      var links = root.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) strip(links[i]);
    };
    new MutationObserver(function (mutations) {
      mutations.forEach(function (m) {
        if (m.type === 'attributes') strip(m.target);
        else m.addedNodes.forEach(stripAll);
      });
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['href'] });
    document.addEventListener('click', function (e) {
      if (e.defaultPrevented) return;
      var a = e.target.closest && e.target.closest('a[data-app-href]');
      if (!a) return;
      var href = a.getAttribute('data-app-href');
      if (!href || href === '#' || /^javascript:/i.test(href)) return;
      e.preventDefault();
      // mailto:, tel: et sites externes : l'appli les ouvre dans l'appli du
      // téléphone (Mail, Safari…), comme le faisait le lien.
      if (a.target === '_blank') window.open(href, '_blank');
      else location.href = href;
    });
  }
})();
