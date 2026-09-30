import 'package:flutter/material.dart';

class VerificationUploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool uploaded;
  final VoidCallback onUpload;

  const VerificationUploadCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.uploaded,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: IconButton(
          onPressed: onUpload,
          icon: Icon(uploaded ? Icons.check_circle : Icons.upload_file),
        ),
      ),
    );
  }
}
