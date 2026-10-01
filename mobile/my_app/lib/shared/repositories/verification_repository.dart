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
  rateLimited,
  authentication,
  conflict,
  unavailable,
  invalidUpload,
  network,
  unknown,
}

class FaceVerificationException implements Exception {
  const FaceVerificationException(this.failure, this.message);

  final FaceVerificationFailure failure;
  final String message;

  @override
  String toString() => message;
}

class FaceVerificationResult {
  const FaceVerificationResult({this.confidence, this.bypassed = false});

  final double? confidence;
  final bool bypassed;
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

  // TODO(face-verification): temporary ID-only mode. facePhoto is optional
  // while the backend bypass is enabled; restore `required File facePhoto`
  // to re-enable face matching.
  Future<FaceVerificationResult> submit({
    required String idType,
    required String idNumber,
    required File governmentId,
    File? facePhoto,
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
    if (facePhoto != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'selfie',
          facePhoto.path,
          contentType: _contentType(facePhoto),
        ),
      );
    }

    try {
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      final payload = _json(response.body);
      if (response.statusCode == 201 && payload['match'] == true) {
        return FaceVerificationResult(
          confidence: (payload['confidence'] as num?)?.toDouble(),
          bypassed: payload['bypassed'] == true,
        );
      }
      final code = payload['code']?.toString();
      final message = payload['message']?.toString();
      throw FaceVerificationException(
        _failureFor(response.statusCode, code),
        message ?? _defaultMessage(response.statusCode, code),
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

  MediaType _contentType(File file) => file.path.toLowerCase().endsWith('.png')
      ? MediaType('image', 'png')
      : MediaType('image', 'jpeg');

  FaceVerificationFailure _failureFor(int status, String? code) {
    if (code == 'FACE_MISMATCH') return FaceVerificationFailure.mismatch;
    if (code == 'FACE_NOT_DETECTED') return FaceVerificationFailure.noFace;
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
