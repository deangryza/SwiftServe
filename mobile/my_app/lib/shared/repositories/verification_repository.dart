import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../models/app_user.dart';

enum FaceVerificationFailure {
  mismatch,
  noFace,
  multipleFaces,
  rateLimited,
  authentication,
  conflict,
  unavailable,
  invalidUpload,
  network,
  unknown,
}

/// Which uploaded photo a face-detection failure refers to.
enum VerificationImage { document, selfie }

class FaceVerificationException implements Exception {
  const FaceVerificationException(
    this.failure,
    this.message, {
    this.similarity,
    this.image,
  });

  final FaceVerificationFailure failure;
  final String message;

  /// Calibrated similarity percentage, present on a face mismatch.
  final double? similarity;

  /// The photo the server could not use, present on face-detection failures.
  final VerificationImage? image;

  @override
  String toString() => message;
}

class FaceVerificationResult {
  const FaceVerificationResult({
    this.similarity,
    this.confidence,
    this.band,
    this.status,
  });

  /// Calibrated similarity percentage (0–100).
  final double? similarity;
  final double? confidence;

  /// `strong` (auto-verified) or `borderline` (sent to admin review).
  final String? band;

  /// Verification status after submission: `verified` or `pending`.
  final String? status;

  bool get isVerified => status == 'verified';
}

class VerificationRepository {
  VerificationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _client;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String uid) =>
      _firestore.collection('worker_verifications').doc(uid).snapshots();

  Stream<VerificationStatus?> watchStatus(String uid) => watch(uid).map(
    (document) => document.exists
        ? VerificationStatus.fromWire(document.data()?['status'])
        : null,
  );

  Future<FaceVerificationResult> submit({
    required String idType,
    required String idNumber,
    required File governmentId,
    required File facePhoto,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FaceVerificationException(
        FaceVerificationFailure.authentication,
        'Your session expired. Sign in and try again.',
      );
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/api/verify'),
    );
    request.headers['Authorization'] = 'Bearer ${await user.getIdToken(true)}';
    request.fields.addAll({'idType': idType, 'idNumber': idNumber});
    request.files.add(
      await http.MultipartFile.fromPath(
        'document',
        governmentId.path,
        contentType: _contentType(governmentId),
      ),
    );
    request.files.add(
      await http.MultipartFile.fromPath(
        'selfie',
        facePhoto.path,
        contentType: _contentType(facePhoto),
      ),
    );

    try {
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      final payload = _json(response.body);
      if (response.statusCode == 201 && payload['match'] == true) {
        final verification = payload['verification'];
        return FaceVerificationResult(
          similarity: _number(payload['similarity'] ?? payload['confidence']),
          confidence: _number(payload['confidence'] ?? payload['similarity']),
          band: payload['band']?.toString(),
          status: verification is Map
              ? verification['status']?.toString()
              : null,
        );
      }
      final code = payload['code']?.toString();
      final message = payload['message']?.toString();
      throw FaceVerificationException(
        _failureFor(response.statusCode, code),
        message ?? _defaultMessage(response.statusCode, code),
        similarity: _number(payload['similarity'] ?? payload['confidence']),
        image: switch (payload['image']) {
          'document' => VerificationImage.document,
          'selfie' => VerificationImage.selfie,
          _ => null,
        },
      );
    } on FaceVerificationException {
      rethrow;
    } on SocketException {
      throw const FaceVerificationException(
        FaceVerificationFailure.network,
        'Could not reach the verification service. Check your connection.',
      );
    } on http.ClientException {
      throw const FaceVerificationException(
        FaceVerificationFailure.network,
        'The connection to the verification service failed.',
      );
    }
  }

  Map<String, dynamic> _json(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  double? _number(Object? value) => value is num ? value.toDouble() : null;

  MediaType _contentType(File file) => file.path.toLowerCase().endsWith('.png')
      ? MediaType('image', 'png')
      : MediaType('image', 'jpeg');

  FaceVerificationFailure _failureFor(int status, String? code) {
    if (code == 'FACE_MISMATCH') return FaceVerificationFailure.mismatch;
    if (code == 'FACE_NOT_DETECTED') return FaceVerificationFailure.noFace;
    if (code == 'MULTIPLE_FACES_DETECTED') {
      return FaceVerificationFailure.multipleFaces;
    }
    if (status == 401 || status == 403) {
      return FaceVerificationFailure.authentication;
    }
    if (status == 409) return FaceVerificationFailure.conflict;
    if (status == 429) return FaceVerificationFailure.rateLimited;
    if (status == 503) return FaceVerificationFailure.unavailable;
    if (status == 400 || status == 413 || status == 415) {
      return FaceVerificationFailure.invalidUpload;
    }
    return FaceVerificationFailure.unknown;
  }

  String _defaultMessage(int status, String? code) {
    if (code == 'FACE_MISMATCH') {
      return 'The selfie did not match the face on the ID.';
    }
    if (status == 429) return 'Too many attempts. Try again later.';
    if (status == 503) return 'Face verification is temporarily unavailable.';
    return 'Verification failed. Please try again.';
  }
}
