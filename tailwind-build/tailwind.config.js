// Mise en forme de l'appli et du logiciel agent, fabriquée une fois pour toutes
// (23/10/2026) au lieu d'être téléchargée et calculée à chaque ouverture de
// page (cdn.tailwindcss.com), ce qui faisait clignoter les pages.
// Même configuration que l'ancien tailwind.config des pages.
// Refaire css/bligo.css après toute modification de classe : voir build.sh.
module.exports = {
    content: ['../*.html', '!../superadmin.html', '../js/*.js'],
    theme: { extend: {
      fontFamily: { sans: ['Inter', 'sans-serif'], logo: ['Poppins', 'sans-serif'] },
      colors: {
        // Variable pour le thème foncé (28/10/2026) : le texte passe en clair.
        ink: 'rgb(var(--color-ink-rgb, 27 75 67) / <alpha-value>)',
        brand: 'rgb(var(--color-brand-rgb, 27 75 67) / <alpha-value>)',
        mango: { 50:'var(--color-mango-50, #FFF7ED)',100:'var(--color-mango-100, #FFEAD2)',200:'var(--color-mango-200, #FFD4A3)',300:'var(--color-mango-300, #FFB86B)',400:'var(--color-mango-400, #FFA33F)',500:'var(--color-mango-500, #FF9B2E)',600:'var(--color-mango-600, #F07F14)',700:'var(--color-mango-700, #C7630F)',800:'var(--color-mango-800, #9E4E12)',900:'var(--color-mango-900, #7C3F12)' },
        hibiscus: { 50:'var(--color-hibiscus-50, #FFF0F5)',100:'var(--color-hibiscus-100, #FFDCE9)',200:'var(--color-hibiscus-200, #FFB8D3)',300:'var(--color-hibiscus-300, #FF8FB9)',400:'var(--color-hibiscus-400, #F2609A)',500:'var(--color-hibiscus-500, #E8437A)',600:'var(--color-hibiscus-600, #C92C61)',700:'var(--color-hibiscus-700, #A3234E)',800:'var(--color-hibiscus-800, #7E1C3D)',900:'var(--color-hibiscus-900, #5F1730)' }
      }
    } }
  };
