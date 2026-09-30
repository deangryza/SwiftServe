class Verification {
  final String workerId;
  final String status;
  final String? documentUrl;

  const Verification({
    required this.workerId,
    required this.status,
    this.documentUrl,
  });
}
