// lib/models/chapter.dart
class Chapter {
  final String id;
  final String title;
  final String href;
  final int index;
  final List<Chapter> subChapters;

  Chapter({
    required this.id,
    required this.title,
    required this.href,
    required this.index,
    this.subChapters = const [],
  });
}