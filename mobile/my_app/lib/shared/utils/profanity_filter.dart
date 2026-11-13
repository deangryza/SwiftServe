// Masks English and Tagalog bad words in text other users will read.
//
// Keep the word lists and rules in sync with
// swiftserve-backend/src/services/profanityFilter.js.
//
// Matching is per word, so "tangan" (hold) or "petite" are left alone.
// Each word is lowercased, common look-alike characters are mapped back to
// letters (g4g0 -> gago, $hit -> shit) and repeated letters are collapsed
// (gagooo -> gago) before it is compared.

/// Words matched exactly (plus an optional "s" or Tagalog "-ng" ending).
const _exactWords = [
  // Tagalog
  'putangina', 'tangina', 'pucha', 'punyeta', 'gago', 'gaga', 'tanga',
  'bobo', 'ulol', 'ulul', 'tarantado', 'kupal', 'pakyu', 'pakshet', 'inamo',
  'pokpok', 'puta', 'puke', 'pekpek', 'titi', 'tite', 'burat', 'bilat',
  'kantot', 'jakol', 'salsal', 'hindot', 'siraulo', 'engot', 'inutil',
  // English
  'asshole', 'bastard', 'cunt', 'dick', 'pussy', 'slut', 'whore', 'nigger',
  'nigga', 'retard',
];

/// Words that also match anything they start (fucking, shitty, tanginamo).
const _prefixWords = [
  'fuck',
  'motherfuck',
  'shit',
  'bitch',
  'fag',
  'putangina',
  'tangina',
];

/// Two-word insults: the first word is only masked when followed by the second.
const _phrases = {'putang': 'ina', 'tang': 'ina'};

const _lookAlikes = {
  '@': 'a',
  '4': 'a',
  '0': 'o',
  '1': 'i',
  '3': 'e',
  r'$': 's',
  '5': 's',
};

final _token = RegExp(r'[A-Za-z0-9@$]+');

String _collapse(String value) =>
    value.replaceAllMapped(RegExp(r'(.)\1+'), (match) => match.group(1)!);

String _normalize(String word) => _collapse(
  word.toLowerCase().split('').map((c) => _lookAlikes[c] ?? c).join(),
);

final _exact = {for (final w in _exactWords) _collapse(w)};
final _prefixes = [for (final w in _prefixWords) _collapse(w)];

/// Normal words a prefix above would otherwise catch (stored collapsed).
const _allowed = {'shitake'};

bool _isBad(String normalized) {
  if (_allowed.contains(normalized)) return false;
  if (_exact.contains(normalized)) return true;
  for (final ending in const ['s', 'es', 'ng']) {
    if (normalized.endsWith(ending) &&
        _exact.contains(
          normalized.substring(0, normalized.length - ending.length),
        )) {
      return true;
    }
  }
  return _prefixes.any(normalized.startsWith);
}

String _mask(String word) =>
    word.length <= 1 ? word : word[0] + '*' * (word.length - 1);

/// Returns [text] with every bad word replaced by its first letter and stars.
String maskProfanity(String text) {
  if (text.isEmpty) return text;
  final tokens = _token.allMatches(text).toList();
  if (tokens.isEmpty) return text;
  final masked = List<bool>.filled(tokens.length, false);
  for (var i = 0; i < tokens.length; i++) {
    final word = _normalize(tokens[i].group(0)!);
    if (_isBad(word)) masked[i] = true;
    final second = _phrases[word];
    if (second != null &&
        i + 1 < tokens.length &&
        _normalize(tokens[i + 1].group(0)!).startsWith(second)) {
      masked[i] = masked[i + 1] = true;
    }
  }
  if (!masked.contains(true)) return text;
  final out = StringBuffer();
  var last = 0;
  for (var i = 0; i < tokens.length; i++) {
    if (!masked[i]) continue;
    out
      ..write(text.substring(last, tokens[i].start))
      ..write(_mask(tokens[i].group(0)!));
    last = tokens[i].end;
  }
  out.write(text.substring(last));
  return out.toString();
}

/// Whether [text] contains a word [maskProfanity] would hide.
bool containsProfanity(String text) => maskProfanity(text) != text;
