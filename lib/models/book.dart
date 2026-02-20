// lib/models/book.dart
import 'dart:convert';

class Book {
  final String id;
  final String filePath;
  final String title;
  final String? author;
  final String? coverPath;
  final DateTime addedAt;
  final DateTime? lastReadAt;
  final String? lastCfi;
  final double progress; // 0.0 - 1.0

  Book({
    required this.id,
    required this.filePath,
    required this.title,
    this.author,
    this.coverPath,
    required this.addedAt,
    this.lastReadAt,
    this.lastCfi,
    this.progress = 0.0,
  });

  Book copyWith({
    String? id,
    String? filePath,
    String? title,
    String? author,
    String? coverPath,
    DateTime? addedAt,
    DateTime? lastReadAt,
    String? lastCfi,
    double? progress,
  }) {
    return Book(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      addedAt: addedAt ?? this.addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      lastCfi: lastCfi ?? this.lastCfi,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'title': title,
      'author': author,
      'coverPath': coverPath,
      'addedAt': addedAt.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
      'lastCfi': lastCfi,
      'progress': progress,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'],
      filePath: map['filePath'],
      title: map['title'],
      author: map['author'],
      coverPath: map['coverPath'],
      addedAt: DateTime.parse(map['addedAt']),
      lastReadAt: map['lastReadAt'] != null ? DateTime.parse(map['lastReadAt']) : null,
      lastCfi: map['lastCfi'],
      progress: (map['progress'] ?? 0.0).toDouble(),
    );
  }

  String toJson() => json.encode(toMap());
  factory Book.fromJson(String source) => Book.fromMap(json.decode(source));
}