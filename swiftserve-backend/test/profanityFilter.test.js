const test = require('node:test');
const assert = require('node:assert/strict');
const { maskProfanity, containsProfanity } = require('../src/services/profanityFilter');

// Same cases as mobile/my_app/test/profanity_filter_test.dart.
test('masks Tagalog and English words, keeping the first letter', () => {
  assert.equal(maskProfanity('gago ka'), 'g*** ka');
  assert.equal(maskProfanity('Ang tanga mo talaga'), 'Ang t**** mo talaga');
  assert.equal(maskProfanity('what the fuck'), 'what the f***');
});

test('ignores case and keeps punctuation', () => {
  assert.equal(maskProfanity('GAGO!'), 'G***!');
  assert.equal(maskProfanity('Bobo, ulol.'), 'B***, u***.');
});

test('catches look-alike characters, stretched letters, endings and prefixes', () => {
  assert.equal(maskProfanity('g4g0'), 'g***');
  assert.equal(maskProfanity('$hit'), '$***');
  assert.equal(maskProfanity('gagooooo'), 'g*******');
  assert.equal(maskProfanity('fucking late'), 'f****** late');
  assert.equal(maskProfanity('tanginamo'), 't********');
  assert.equal(maskProfanity('gagong worker'), 'g***** worker');
});

test('masks two-word insults', () => {
  assert.equal(maskProfanity('putang ina mo'), 'p***** i** mo');
  assert.equal(maskProfanity('tang ina'), 't*** i**');
});

test('leaves normal words and non-strings alone', () => {
  for (const text of ['Pakihawakan mo, tangan ko na', 'Petite dress alteration', 'Mr. Dickson will meet you',
    'Ang ina mo ay mabait', 'Leche flan for 20 pax, PHP 500', 'Salamat po sa tulong!',
    'Shiitake mushrooms from the market', '']) {
    assert.equal(maskProfanity(text), text, text);
    assert.equal(containsProfanity(text), false, text);
  }
  assert.equal(maskProfanity(undefined), undefined);
  assert.equal(maskProfanity(42), 42);
});
