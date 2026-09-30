class Worker {
  final String id;
  final String name;
  final String email;
  final String service;
  final String status;

  const Worker({
    required this.id,
    required this.name,
    required this.email,
    this.service = '',
    this.status = 'pending',
  });

  factory Worker.fromMap(String id, Map<String, dynamic> data) => Worker(
    id: id,
    name: data['name'] ?? '',
    email: data['email'] ?? '',
    service: data['service'] ?? '',
    status: data['status'] ?? 'pending',
  );
}
