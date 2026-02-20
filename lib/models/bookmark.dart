// lib/models/bookmark.dart
import 'dart:convert';

class Bookmark {
  final String id;
  final String bookId;
  final String cfi;
  final String? title;
  final String? excerpt;
  final int? chapterIndex;
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.bookId,
    required this.cfi,
    this.title,
    this.excerpt,
    this.chapterIndex,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'cfi': cfi,
      'title': title,
      'excerpt': excerpt,
      'chapterIndex': chapterIndex,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'],
      bookId: map['bookId'],
      cfi: map['cfi'],
      title: map['title'],
      excerpt: map['excerpt'],
      chapterIndex: map['chapterIndex'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  String toJson() => json.encode(toMap());
  factory Bookmark.fromJson(String source) => Bookmark.fromMap(json.decode(source));
}