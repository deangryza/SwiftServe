import 'package:flutter/material.dart';

class CategoryModel {
  const CategoryModel({
    required this.title,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
}

const List<CategoryModel> categories = [
  CategoryModel(
    title: 'Home\nServices',
    icon: Icons.home_outlined,
    iconColor: Colors.orange,
  ),
  CategoryModel(
    title: 'Academic\nHelp',
    icon: Icons.menu_book_outlined,
    iconColor: Colors.green,
  ),
  CategoryModel(
    title: 'Repairs',
    icon: Icons.build_outlined,
    iconColor: Colors.grey,
  ),
  CategoryModel(
    title: 'Errands',
    icon: Icons.pedal_bike_outlined,
    iconColor: Colors.pink,
  ),
  CategoryModel(
    title: 'Cleaning',
    icon: Icons.auto_awesome_outlined,
    iconColor: Colors.blue,
  ),
  CategoryModel(
    title: 'Beauty',
    icon: Icons.content_cut_outlined,
    iconColor: Colors.purple,
  ),
];
