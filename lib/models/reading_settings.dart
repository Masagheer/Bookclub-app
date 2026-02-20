// lib/models/reading_settings.dart
import 'dart:convert';
import 'package:flutter/material.dart';

class ReadingSettings {
  final ReaderTheme theme;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final TextAlign textAlign;
  final double margin;

  const ReadingSettings({
    this.theme = ReaderTheme.light,
    this.fontFamily = 'Georgia',
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.textAlign = TextAlign.justify,
    this.margin = 16.0,
  });

  ReadingSettings copyWith({
    ReaderTheme? theme,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    TextAlign? textAlign,
    double? margin,
  }) {
    return ReadingSettings(
      theme: theme ?? this.theme,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlign: textAlign ?? this.textAlign,
      margin: margin ?? this.margin,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'theme': theme.index,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'textAlign': textAlign.index,
      'margin': margin,
    };
  }

  factory ReadingSettings.fromMap(Map<String, dynamic> map) {
    return ReadingSettings(
      theme: ReaderTheme.values[map['theme'] ?? 0],
      fontFamily: map['fontFamily'] ?? 'Georgia',
      fontSize: (map['fontSize'] ?? 18.0).toDouble(),
      lineHeight: (map['lineHeight'] ?? 1.6).toDouble(),
      textAlign: TextAlign.values[map['textAlign'] ?? 3],
      margin: (map['margin'] ?? 16.0).toDouble(),
    );
  }

  String toJson() => json.encode(toMap());
  factory ReadingSettings.fromJson(String source) => 
      ReadingSettings.fromMap(json.decode(source));
}

enum ReaderTheme {
  light(
    name: 'Light',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF000000),
    accentColor: Color(0xFF2196F3),
  ),
  sepia(
    name: 'Sepia',
    backgroundColor: Color(0xFFF4ECD8),
    textColor: Color(0xFF5B4636),
    accentColor: Color(0xFF8B4513),
  ),
  dark(
    name: 'Dark',
    backgroundColor: Color(0xFF1A1A1A),
    textColor: Color(0xFFE0E0E0),
    accentColor: Color(0xFF64B5F6),
  ),
  black(
    name: 'Black',
    backgroundColor: Color(0xFF000000),
    textColor: Color(0xFFCCCCCC),
    accentColor: Color(0xFF90CAF9),
  );

  final String name;
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;

  const ReaderTheme({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
  });
}