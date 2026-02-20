// lib/models/highlight.dart
import 'dart:convert';
import 'dart:ui';

class Highlight {
  final String id;
  final String bookId;
  final String cfi;
  final String text;
  final String? note;
  final HighlightColor color;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String userId; // For multi-user support
  final int commentCount; // Cached count for UI

  Highlight({
    required this.id,
    required this.bookId,
    required this.cfi,
    required this.text,
    this.note,
    this.color = HighlightColor.yellow,
    required this.createdAt,
    this.updatedAt,
    required this.userId,
    this.commentCount = 0,
  });

  Highlight copyWith({
    String? id,
    String? bookId,
    String? cfi,
    String? text,
    String? note,
    HighlightColor? color,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
    int? commentCount,
  }) {
    return Highlight(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      cfi: cfi ?? this.cfi,
      text: text ?? this.text,
      note: note ?? this.note,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
      commentCount: commentCount ?? this.commentCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'cfi': cfi,
      'text': text,
      'note': note,
      'color': color.index,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'userId': userId,
      'commentCount': commentCount,
    };
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    return Highlight(
      id: map['id'],
      bookId: map['bookId'],
      cfi: map['cfi'],
      text: map['text'],
      note: map['note'],
      color: HighlightColor.values[map['color'] ?? 0],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      userId: map['userId'],
      commentCount: map['commentCount'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());
  factory Highlight.fromJson(String source) => Highlight.fromMap(json.decode(source));
}

enum HighlightColor {
  yellow(Color(0xFFFFEB3B), 'Yellow'),
  green(Color(0xFF4CAF50), 'Green'),
  blue(Color(0xFF2196F3), 'Blue'),
  pink(Color(0xFFE91E63), 'Pink'),
  purple(Color(0xFF9C27B0), 'Purple'),
  orange(Color(0xFFFF9800), 'Orange');

  final Color color;
  final String name;
  const HighlightColor(this.color, this.name);

  String get cssColor {
    return 'rgba(${color.red}, ${color.green}, ${color.blue}, 0.4)';
  }
}