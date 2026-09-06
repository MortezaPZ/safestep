import fa from './i18n/fa.js';
import en from './i18n/en.js';

const dict = { fa, en };

let current = localStorage.getItem('safestep.lang') || 'fa';

export function t(key) {
  return dict[current]?.[key] ?? dict.fa[key] ?? key;
}

export function getLang() {
  return current;
}

export function setLang(lang) {
  current = lang === 'en' ? 'en' : 'fa';
  localStorage.setItem('safestep.lang', current);
  document.documentElement.lang = current;
  document.documentElement.dir = current === 'fa' ? 'rtl' : 'ltr';
}

setLang(current);

export default { t, getLang, setLang };
