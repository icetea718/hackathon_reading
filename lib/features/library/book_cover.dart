import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final Book book;

  static const _serifFallbacks = [
    'Noto Serif CJK SC',
    'SimSun',
    'Georgia',
  ];

  static List<Color> _paletteFor(BookFormat format) => switch (format) {
        BookFormat.txt => const [Color(0xFF7080A8), Color(0xFF4C5878)],
        BookFormat.epub => const [Color(0xFF6C9183), Color(0xFF48695E)],
        BookFormat.pdf => const [Color(0xFFA88070), Color(0xFF7A5848)],
      };

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
    final colors = _paletteFor(book.format);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final titleSize = (width * 0.14).clamp(14.0, 30.0);
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
              Positioned(
                left: 8,
                top: 8,
                right: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                child: Center(
                  child: Text(
                    book.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: 1.0,
                      fontFamily: 'Source Han Serif SC',
                      fontFamilyFallback: _serifFallbacks,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
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
      },
    );
  }
}
