import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/upload_card.dart';
import '../widgets/preview_card.dart';
import '../widgets/location_card.dart';
import '../widgets/privacy_card.dart';
import '../widgets/submit_button.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {

  File? validIdImage;
  File? optionalImage;

  String? idFileName;
  String? optionalFile;

  bool locationEnabled = false;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.black,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "Identity Verification",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Text(
                "Verify Your Identity",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                "Upload your valid ID and complete the verification process to continue using SwiftServe.",
                style: TextStyle(
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 25),

              UploadCard(
                requiredUpload: true,
                title: "Upload Valid ID",
                subtitle: "Passport, Driver's License or National ID",
                fileName: idFileName,
                onSelected: (file, name) {
                  setState(() {
                    validIdImage = file;
                    idFileName = name;
                  });
                },
              ),

              const SizedBox(height: 20),

              UploadCard(
                requiredUpload: false,
                title: "Optional Proof of Identity",
                subtitle: "Utility Bill or Bank Statement",
                fileName: optionalFile,
                onSelected: (file, name) {
                  setState(() {
                    optionalImage = file;
                    optionalFile = name;
                  });
                },
              ),

              const SizedBox(height: 20),

              PreviewCard(
                image: validIdImage,
              ),

              const SizedBox(height: 20),

              LocationCard(
                value: locationEnabled,
                onChanged: (value) {
                  setState(() {
                    locationEnabled = value;
                  });
                },
              ),

              const SizedBox(height: 20),

              const PrivacyCard(),

              const SizedBox(height: 30),

              SubmitButton(
                loading: loading,
                onPressed: () async {

                  if (idFileName == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please upload your Valid ID.",
                        ),
                      ),
                    );
                    return;
                  }

                  setState(() {
                    loading = true;
                  });

                  await Future.delayed(
                    const Duration(seconds: 2),
                  );

                  setState(() {
                    loading = false;
                  });

                  // TODO:
                  // Upload to Firebase
                  // Go to Review Screen
                },
              ),

              const SizedBox(height: 30),

            ],
          ),
        ),
      ),
    );
  }
}