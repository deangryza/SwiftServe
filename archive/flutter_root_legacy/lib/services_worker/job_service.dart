import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'api_service.dart';

class JobService {
  final ApiService api = ApiService();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<List<Job>> getAvailableJobs() {
    return api.getAvailableJobs();
  }

  Future<void> acceptJob(String jobId, String workerId) {
    return api.acceptJob(jobId, workerId);
  }

  Future<void> updateStatus(String jobId, String status, String workerId) {
    return api.updateJobStatus(jobId, status, workerId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchWorkerJobs(String workerId) {
    return firestore
        .collection('jobs')
        .where('workerId', isEqualTo: workerId)
        .snapshots();
  }
}
