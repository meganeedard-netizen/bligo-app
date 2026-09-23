// BliGO — thème personnalisé par médiathèque (22/09/2026)
//
// Chaque page usager utilise déjà les couleurs Tailwind "ink"/"mango"/
// "hibiscus" partout (voir tailwind.config de chaque page, qui les résout
// depuis des variables CSS --color-*). Changer ces variables suffit donc à
// re-teinter toute la page sans toucher un seul nom de classe existant.
//
// "mango" et "hibiscus" pointent vers LE MÊME dégradé généré à partir d'une
// seule couleur choisie par la médiathèque (ex. un dégradé de jaune) — sur
// demande explicite de Mégane, plus simple qu'un vrai dégradé à deux teintes
// pour une couleur quelconque.

function hexToHsl(hex) {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = (g - b) / d + (g < b ? 6 : 0); break;
      case g: h = (b - r) / d + 2; break;
      default: h = (r - g) / d + 4;
    }
    h /= 6;
  }
  return [h * 360, s * 100, l * 100];
}

function hslToHex(h, s, l) {
  s /= 100; l /= 100;
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs((h / 60) % 2 - 1));
  const m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  const toHex = v => Math.round((v + m) * 255).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

// Calqué sur l'allure de la palette mango/hibiscus d'origine (50 très clair,
// 900 très sombre) pour que le rendu reste cohérent quelle que soit la
// couleur choisie.
const RAMP_LIGHTNESS = { 50: 95, 100: 89, 200: 78, 300: 66, 400: 56, 500: 49, 600: 40, 700: 32, 800: 25, 900: 19 };

export function generateRamp(baseHex) {
  const [h, s] = hexToHsl(baseHex);
  const sat = Math.max(s, 55); // évite une palette trop grisée si la couleur choisie est pâle
  const ramp = {};
  for (const step in RAMP_LIGHTNESS) ramp[step] = hslToHex(h, sat, RAMP_LIGHTNESS[step]);
  return ramp;
}

const CACHE_KEY = 'bligo_theme';

function setVars(inkHex, accentHex) {
  const root = document.documentElement.style;
  if (inkHex) root.setProperty('--color-ink', inkHex);
  if (accentHex) {
    const ramp = generateRamp(accentHex);
    for (const step in ramp) {
      root.setProperty(`--color-mango-${step}`, ramp[step]);
      root.setProperty(`--color-hibiscus-${step}`, ramp[step]);
    }
  }
}

// À appeler tout de suite au chargement de chaque page, avant même de savoir
// à quelle médiathèque appartient l'usager — évite un flash des couleurs par
// défaut le temps de recharger sa commune depuis Supabase. Jamais la seule
// source de vérité, juste un raccourci depuis la dernière fois.
export function applyCachedTheme() {
  try {
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null');
    if (cached) setVars(cached.ink, cached.accent);
  } catch {}
}

// À appeler après avoir chargé la commune de l'usager (theme_ink_hex,
// theme_accent_hex) — applique le vrai thème et le met en cache pour que les
// prochaines pages (qui ne rechargent pas toutes la commune) l'aient déjà.
export function applyCommuneTheme(commune) {
  const ink = commune?.theme_ink_hex || null;
  const accent = commune?.theme_accent_hex || null;
  setVars(ink, accent);
  try { localStorage.setItem(CACHE_KEY, JSON.stringify({ ink, accent })); } catch {}
}
