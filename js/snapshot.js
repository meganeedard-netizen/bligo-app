// Affichage instantané des pages de l'appli (23/10/2026).
// En quittant une page, son contenu est mémorisé sur le téléphone. À la visite
// suivante, il est réaffiché tout de suite (sans attendre le serveur), pendant
// que la page charge les données à jour en arrière-plan ; dès qu'elles sont
// prêtes, la vraie page remplace l'instantané. Script classique (pas un
// module) placé juste après </main>, pour s'exécuter avant le premier affichage.
// L'instantané n'est montré qu'au même compte (ou au même visiteur et à la
// même médiathèque) ; il est effacé à la déconnexion (voir index.html).
(function () {
  var KEY = 'bligo_snap_' + (location.pathname.split('/').pop() || 'index.html');
  var MAX_AGE = 7 * 24 * 3600 * 1000;
  var main = document.querySelector('main');

  function owner() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k)) {
          var s = JSON.parse(localStorage.getItem(k));
          if (s && s.user && s.user.id) return s.user.id;
        }
      }
      return 'guest:' + (localStorage.getItem('bligo_guest_commune_id') || '');
    } catch (e) { return null; }
  }
  var me = owner();

  try {
    var snap = JSON.parse(localStorage.getItem(KEY) || 'null');
    if (main && me && snap && snap.o === me && Date.now() - snap.t < MAX_AGE) {
      var copy = document.createElement('div');
      copy.id = 'page-snapshot';
      copy.className = main.className;
      copy.innerHTML = snap.h;
      // Pas d'identifiants en double avec la vraie page, et pas de clic tant
      // que les données à jour ne sont pas là (moins d'une seconde).
      copy.querySelectorAll('[id]').forEach(function (el) { el.removeAttribute('id'); });
      copy.setAttribute('aria-hidden', 'true');
      copy.style.pointerEvents = 'none';
      main.parentNode.insertBefore(copy, main);
      document.documentElement.classList.add('has-snapshot');
    }
  } catch (e) {}

  function save() {
    try {
      if (!main || !me || document.documentElement.classList.contains('page-loading')) return;
      localStorage.setItem(KEY, JSON.stringify({ o: me, t: Date.now(), h: main.innerHTML }));
    } catch (e) {}
  }

  // Appelé par la page quand ses données sont chargées.
  window.bligoPageReady = function () {
    var copy = document.getElementById('page-snapshot');
    if (copy) copy.remove();
    document.documentElement.classList.remove('page-loading', 'has-snapshot');
    setTimeout(save, 400);
  };
  window.addEventListener('pagehide', save);
})();
