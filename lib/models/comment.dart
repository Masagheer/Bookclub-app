// lib/models/comment.dart
import 'dart:convert';

class Comment {
  final String id;
  final String highlightId;
  final String bookId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String body;
  final String? parentId; // For replies
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<Comment> replies; // Populated when loading

  Comment({
    required this.id,
    required this.highlightId,
    required this.bookId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.body,
    this.parentId,
    required this.createdAt,
    this.updatedAt,
    this.replies = const [],
  });

  Comment copyWith({
    String? id,
    String? highlightId,
    String? bookId,
    String? userId,
    String? userName,
    String? userAvatar,
    String? body,
    String? parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Comment>? replies,
  }) {
    return Comment(
      id: id ?? this.id,
      highlightId: highlightId ?? this.highlightId,
      bookId: bookId ?? this.bookId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      body: body ?? this.body,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      replies: replies ?? this.replies,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'highlightId': highlightId,
      'bookId': bookId,
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'body': body,
      'parentId': parentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Comment.fromMap(Map<String, dynamic> map) {
    return Comment(
      id: map['id'],
      highlightId: map['highlightId'],
      bookId: map['bookId'],
      userId: map['userId'],
      userName: map['userName'],
      userAvatar: map['userAvatar'],
      body: map['body'],
      parentId: map['parentId'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  String toJson() => json.encode(toMap());
  factory Comment.fromJson(String source) => Comment.fromMap(json.decode(source));
}