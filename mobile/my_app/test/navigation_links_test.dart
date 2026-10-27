import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/utils/navigation_links.dart';

void main() {
  const stop = JobCoordinate(latitude: 14.8401, longitude: 120.8112);

  test('Android Google Maps navigates straight to the coordinate first', () {
    final links = navigationLinks(
      NavigationApp.googleMaps,
      stop,
      android: true,
    );

    expect(
      links.first.toString(),
      'google.navigation:q=14.8401,120.8112&mode=d',
    );
    expect(links.last.host, 'www.google.com');
    expect(links.last.queryParameters['destination'], '14.8401,120.8112');
  });

  test('other platforms use the web directions link', () {
    final links = navigationLinks(
      NavigationApp.googleMaps,
      stop,
      android: false,
    );

    expect(links, hasLength(1));
    expect(links.single.queryParameters['dir_action'], 'navigate');
  });

  test('Waze navigates to the coordinate', () {
    final link = navigationLinks(
      NavigationApp.waze,
      stop,
      android: true,
    ).single;

    expect(link.host, 'waze.com');
    expect(link.queryParameters['ll'], '14.8401,120.8112');
    expect(link.queryParameters['navigate'], 'yes');
  });
}
