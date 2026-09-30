import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UploadCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool requiredUpload;
  final String? fileName;
  final Function(File?, String?) onSelected;

  const UploadCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.requiredUpload,
    required this.fileName,
    required this.onSelected,
  });

  @override
  State<UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends State<UploadCard> {
  final ImagePicker picker = ImagePicker();

  File? image;
  bool isPdf = false;

  Future<void> pickCamera() async {
    final XFile? file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (file != null) {
      setState(() {
        image = File(file.path);
        isPdf = false;
      });

      widget.onSelected(File(file.path), file.name);
    }
  }

  Future<void> pickGallery() async {
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file != null) {
      setState(() {
        image = File(file.path);
        isPdf = false;
      });

      widget.onSelected(File(file.path), file.name);
    }
  }

  Future<void> pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        image = null;
        isPdf = true;
      });

      widget.onSelected(null, result.files.single.name);
    }
  }

  void showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context);
                  pickCamera();
                },
              ),

              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  pickGallery();
                },
              ),

              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text("Choose PDF"),
                onTap: () {
                  Navigator.pop(context);
                  pickPdf();
                },
              ),

              ListTile(
                leading: const Icon(Icons.close),
                title: const Text("Cancel"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),

              if (widget.requiredUpload)
                const Text(
                  " *",
                  style: TextStyle(color: Colors.red, fontSize: 18),
                ),
            ],
          ),

          const SizedBox(height: 6),

          Text(widget.subtitle, style: TextStyle(color: Colors.grey.shade600)),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(image!, fit: BoxFit.cover),
                  )
                : isPdf
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red, size: 55),

                      SizedBox(height: 10),

                      Text(
                        "PDF Selected",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 55,
                        color: Colors.grey.shade500,
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        "No file selected",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 15),

          if (widget.fileName != null)
            Text(
              widget.fileName!,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: showPicker,
              icon: const Icon(Icons.upload_file),
              label: const Text("Select File"),
            ),
          ),
        ],
      ),
    );
  }
}
