import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/job_location.dart';

/// A driving route along real roads.
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<JobCoordinate> points;
  final double distanceMeters;
  final double durationSeconds;

  factory RoadRoute.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((point) {
          final pair = point as List;
          return JobCoordinate(
            latitude: (pair[0] as num).toDouble(),
            longitude: (pair[1] as num).toDouble(),
          );
        })
        .toList(growable: false);
    if (points.length < 2) {
      throw const FormatException('A route needs at least two points.');
    }
    return RoadRoute(
      points: points,
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
    );
  }
}

/// Asks the SwiftServe backend for the road route between two points. The
/// backend holds the routing key, so it never ships inside the app.
class RoadRouteService {
  RoadRouteService({http.Client? client, Future<String?> Function()? idToken})
    : _client = client ?? http.Client(),
      _idToken =
          idToken ??
          (() async => FirebaseAuth.instance.currentUser?.getIdToken());

  static final instance = RoadRouteService();

  static const _requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  final Future<String?> Function() _idToken;
  // Shared by every map, including requests still in flight, so maps that
  // open together make one call.
  final _routes = <String, Future<RoadRoute?>>{};

  /// The route, or null when it cannot be found right now; callers then
  /// fall back to a straight line.
  Future<RoadRoute?> fetch(JobCoordinate from, JobCoordinate to) {
    final key = '${_round(from)}|${_round(to)}';
    return _routes[key] ??= _request(from, to).then((route) {
      // Let a failed lookup be tried again next time.
      if (route == null) _routes.remove(key);
      return route;
    });
  }

  Future<RoadRoute?> _request(JobCoordinate from, JobCoordinate to) async {
    try {
      final token = await _idToken();
      if (token == null) return null;
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/routes/errand'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'from': _toJson(from), 'to': _toJson(to)}),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      return RoadRoute.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, double> _toJson(JobCoordinate point) => {
    'lat': point.latitude,
    'lng': point.longitude,
  };

  static String _round(JobCoordinate point) =>
      '${point.latitude.toStringAsFixed(5)},'
      '${point.longitude.toStringAsFixed(5)}';
}
