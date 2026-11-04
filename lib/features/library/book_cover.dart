import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final Book book;

  static const List<List<Color>> _gradients = [
    [Color(0xFF7080A8), Color(0xFF4C5878)],
    [Color(0xFFA88070), Color(0xFF7A5848)],
    [Color(0xFF6C9183), Color(0xFF48695E)],
    [Color(0xFF82758F), Color(0xFF5A4F68)],
    [Color(0xFF8A9070), Color(0xFF5E6548)],
    [Color(0xFF6E7FA0), Color(0xFF4A5A78)],
  ];

  static int gradientIndex(String seed) {
    var hash = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % _gradients.length;
  }

  static String initialLetter(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '书';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final colors = _gradients[gradientIndex(book.id)];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initialLetter(book.title),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Text(
              book.format.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
