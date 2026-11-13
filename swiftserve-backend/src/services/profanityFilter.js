// Masks English and Tagalog bad words in profile text other users will read.
//
// Keep the word lists and rules in sync with
// mobile/my_app/lib/shared/utils/profanity_filter.dart.
//
// Matching is per word, so "tangan" (hold) or "petite" are left alone.
// Each word is lowercased, common look-alike characters are mapped back to
// letters (g4g0 -> gago, $hit -> shit) and repeated letters are collapsed
// (gagooo -> gago) before it is compared.

// Words matched exactly (plus an optional "s"/"es" or Tagalog "-ng" ending).
const EXACT_WORDS = [
  // Tagalog
  'putangina', 'tangina', 'pucha', 'punyeta', 'gago', 'gaga', 'tanga',
  'bobo', 'ulol', 'ulul', 'tarantado', 'kupal', 'pakyu', 'pakshet', 'inamo',
  'pokpok', 'puta', 'puke', 'pekpek', 'titi', 'tite', 'burat', 'bilat',
  'kantot', 'jakol', 'salsal', 'hindot', 'siraulo', 'engot', 'inutil',
  // English
  'asshole', 'bastard', 'cunt', 'dick', 'pussy', 'slut', 'whore', 'nigger',
  'nigga', 'retard',
];

// Words that also match anything they start (fucking, shitty, tanginamo).
const PREFIX_WORDS = ['fuck', 'motherfuck', 'shit', 'bitch', 'fag', 'putangina', 'tangina'];

// Two-word insults: the first word is only masked when followed by the second.
const PHRASES = { putang: 'ina', tang: 'ina' };

const LOOK_ALIKES = { '@': 'a', 4: 'a', 0: 'o', 1: 'i', 3: 'e', $: 's', 5: 's' };

const collapse = value => value.replace(/(.)\1+/g, '$1');
const normalize = word => collapse([...word.toLowerCase()].map(c => LOOK_ALIKES[c] ?? c).join(''));

const exact = new Set(EXACT_WORDS.map(collapse));
const prefixes = PREFIX_WORDS.map(collapse);
// Normal words a prefix above would otherwise catch (stored collapsed).
const allowed = new Set(['shitake']);

const isBad = (normalized) => {
  if (allowed.has(normalized)) return false;
  if (exact.has(normalized)) return true;
  if (['s', 'es', 'ng'].some(ending => normalized.endsWith(ending)
    && exact.has(normalized.slice(0, -ending.length)))) return true;
  return prefixes.some(prefix => normalized.startsWith(prefix));
};

const mask = word => (word.length <= 1 ? word : word[0] + '*'.repeat(word.length - 1));

// Returns text with every bad word replaced by its first letter and stars.
// Non-string values are returned unchanged so callers can pass raw input.
const maskProfanity = (text) => {
  if (typeof text !== 'string' || !text) return text;
  const tokens = [...text.matchAll(/[A-Za-z0-9@$]+/g)];
  const masked = tokens.map(() => false);
  tokens.forEach((token, i) => {
    const word = normalize(token[0]);
    if (isBad(word)) masked[i] = true;
    const second = PHRASES[word];
    if (second && i + 1 < tokens.length && normalize(tokens[i + 1][0]).startsWith(second)) {
      masked[i] = true;
      masked[i + 1] = true;
    }
  });
  if (!masked.includes(true)) return text;
  let out = '';
  let last = 0;
  tokens.forEach((token, i) => {
    if (!masked[i]) return;
    out += text.slice(last, token.index) + mask(token[0]);
    last = token.index + token[0].length;
  });
  return out + text.slice(last);
};

const containsProfanity = text => maskProfanity(text) !== text;

module.exports = { maskProfanity, containsProfanity };
