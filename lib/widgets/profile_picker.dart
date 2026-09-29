import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePicker extends StatefulWidget {
  const ProfilePicker({super.key});

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {

  File? image;

  final ImagePicker picker = ImagePicker();

  Future pickCamera() async {

    final XFile? file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if(file != null){

      setState(() {

        image = File(file.path);

      });

    }

  }

  Future pickGallery() async {

    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if(file != null){

      setState(() {

        image = File(file.path);

      });

    }

  }

  void openPicker(){

    showModalBottomSheet(

      context: context,

      shape: const RoundedRectangleBorder(

        borderRadius: BorderRadius.vertical(
          top: Radius.circular(25),
        ),

      ),

      builder: (context){

        return SafeArea(

          child: Wrap(

            children: [

              ListTile(

                leading: const Icon(Icons.camera_alt),

                title: const Text("Take Photo"),

                onTap: (){

                  Navigator.pop(context);

                  pickCamera();

                },

              ),

              ListTile(

                leading: const Icon(Icons.photo),

                title: const Text("Choose from Gallery"),

                onTap: (){

                  Navigator.pop(context);

                  pickGallery();

                },

              ),

              ListTile(

                leading: const Icon(Icons.close),

                title: const Text("Cancel"),

                onTap: (){

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

    return Center(

      child: Stack(

        children: [

          CircleAvatar(

            radius: 55,

            backgroundColor: Colors.grey.shade200,

            backgroundImage:

            image != null

                ? FileImage(image!)

                : null,

            child:

            image == null

                ? const Icon(

              Icons.person,

              size: 55,

              color: Colors.grey,

            )

                : null,

          ),

          Positioned(

            bottom: 0,

            right: 0,

            child: GestureDetector(

              onTap: openPicker,

              child: Container(

                padding: const EdgeInsets.all(10),

                decoration: const BoxDecoration(

                  color: Colors.blue,

                  shape: BoxShape.circle,

                ),

                child: const Icon(

                  Icons.camera_alt,

                  color: Colors.white,

                  size: 20,

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }

}