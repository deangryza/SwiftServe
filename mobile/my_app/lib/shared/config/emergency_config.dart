// SOS only ever dials a demo contact. To demo, run with the number to ring,
// e.g. a teammate's phone:
//   flutter run --dart-define=SOS_DEMO_NUMBER=+639171234567
//
// TODO(launch): before going live, dial the real emergency hotline here
// (911 in the Philippines) and update the "demo" wording in sos_button.dart.
// It is left out on purpose so no build can call it by accident.

/// The number SOS dials. Empty means SOS doesn't dial at all.
const emergencyNumber = String.fromEnvironment(
  'SOS_DEMO_NUMBER',
  defaultValue: '+639171234567',
);

/// How the number is named on SOS buttons.
const emergencyLabel = 'demo contact';
