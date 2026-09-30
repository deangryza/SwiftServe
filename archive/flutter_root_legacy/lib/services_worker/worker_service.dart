import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getWorker(String workerId) async {
    final doc = await firestore.collection('workers').doc(workerId).get();

    return doc.exists ? doc.data() : null;
  }

  Future<void> updateWorker(String workerId, Map<String, dynamic> data) {
    return firestore
        .collection('workers')
        .doc(workerId)
        .set(data, SetOptions(merge: true));
  }
}
