import 'dart:io';
import 'package:my_app/shared/repositories/document_review_repository.dart';

class FakeDocumentReview extends DocumentReviewGateway {
  FakeDocumentReview({this.status = 'DOCUMENT_ACCEPTED', this.error});
  final String? error;
  String status;
  int uploads = 0;
  Map<String, dynamic> get value => {
    'status': status,
    'sessionId': 'synthetic-session',
    'attemptId': 'synthetic-attempt',
    'declaredType': 'National ID',
    'reason': status == 'DOCUMENT_REJECTED'
        ? 'Please upload a supported document. Selfies are not accepted.'
        : '',
  };
  @override
  Future<Map<String, dynamic>> get() async => value;
  @override
  Future<Map<String, dynamic>> submit(
    File file,
    String type,
    Map<String, dynamic> previous,
  ) async {
    uploads++;
    if (error != null) {
      throw DocumentReviewException(
        'Document unreadable. Please upload a clearer image.',
        error,
      );
    }
    return value;
  }

  @override
  Future<File> restore(Map<String, dynamic> record) async =>
      File('synthetic-id.png');
}
