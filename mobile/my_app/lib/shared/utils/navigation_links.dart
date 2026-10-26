import '../models/job_location.dart';

/// Navigation apps the rider can hand an errand stop to.
enum NavigationApp { googleMaps, waze }

/// Free deep links that open [app] with turn-by-turn directions to [stop],
/// best first. No maps API key or billing is involved.
///
/// On Android, Google Maps' `google.navigation:` link starts navigation on
/// the exact coordinate. The web directions link would instead label the
/// stop with the nearest business, which looks like the wrong place, so it
/// is only the fallback (and the iOS link).
List<Uri> navigationLinks(
  NavigationApp app,
  JobCoordinate stop, {
  required bool android,
}) {
  final point = '${stop.latitude},${stop.longitude}';
  return switch (app) {
    NavigationApp.googleMaps => [
      if (android) Uri.parse('google.navigation:q=$point&mode=d'),
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': point,
        'travelmode': 'driving',
        'dir_action': 'navigate',
      }),
    ],
    NavigationApp.waze => [
      Uri.https('waze.com', '/ul', {'ll': point, 'navigate': 'yes'}),
    ],
  };
}
