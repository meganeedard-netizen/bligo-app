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
    var bar = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.StatusBar;
    if (bar) {
      try { bar.setStyle({ style: dark ? 'DARK' : 'LIGHT' }); } catch (e) { /* ancienne version de l'appli */ }
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
})();
