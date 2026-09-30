class Category {
  final String name;
  final String icon;

  const Category({
    required this.name,
    required this.icon,
  });
}

const List<Category> categories = [
  Category(name: 'Plumber', icon: '🔧'),
  Category(name: 'Electrician', icon: '⚡'),
  Category(name: 'House Cleaning', icon: '🧹'),
  Category(name: 'Tutor', icon: '📚'),
  Category(name: 'Aircon Repair', icon: '❄️'),
  Category(name: 'Carpenter', icon: '🪚'),
  Category(name: 'Painter', icon: '🎨'),
  Category(name: 'Others', icon: '🛠️'),
];
