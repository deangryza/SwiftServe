import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/utils/profanity_filter.dart';

void main() {
  group('maskProfanity', () {
    test('masks Tagalog and English words, keeping the first letter', () {
      expect(maskProfanity('gago ka'), 'g*** ka');
      expect(maskProfanity('Ang tanga mo talaga'), 'Ang t**** mo talaga');
      expect(maskProfanity('what the fuck'), 'what the f***');
    });

    test('ignores case and keeps punctuation', () {
      expect(maskProfanity('GAGO!'), 'G***!');
      expect(maskProfanity('Bobo, ulol.'), 'B***, u***.');
    });

    test('catches look-alike characters and stretched letters', () {
      expect(maskProfanity('g4g0'), 'g***');
      expect(maskProfanity(r'$hit'), r'$***');
      expect(maskProfanity('gagooooo'), 'g*******');
    });

    test('catches word endings and prefixes', () {
      expect(maskProfanity('fucking late'), 'f****** late');
      expect(maskProfanity('tanginamo'), 't********');
      expect(maskProfanity('gagong worker'), 'g***** worker');
    });

    test('masks two-word insults', () {
      expect(maskProfanity('putang ina mo'), 'p***** i** mo');
      expect(maskProfanity('tang ina'), 't*** i**');
    });

    test('leaves normal words alone', () {
      const clean = [
        'Pakihawakan mo, tangan ko na',
        'Petite dress alteration',
        'Mr. Dickson will meet you',
        'Ang ina mo ay mabait',
        'Leche flan for 20 pax, PHP 500',
        'Salamat po sa tulong!',
        'Shiitake mushrooms from the market',
        '',
      ];
      for (final text in clean) {
        expect(maskProfanity(text), text, reason: text);
        expect(containsProfanity(text), isFalse, reason: text);
      }
    });
  });
}
