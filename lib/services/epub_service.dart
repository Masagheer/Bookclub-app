// lib/services/epub_service.dart
import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/chapter.dart';

class EpubService {
  static const _uuid = Uuid();

  /// Extract and parse EPUB, returning Book metadata
  Future<Book> importEpub(File epubFile) async {
    final bytes = await epubFile.readAsBytes();
    final epub = await EpubReader.readBook(bytes);
    
    // Create a unique directory for this book
    final bookId = _uuid.v4();
    final appDir = await getApplicationDocumentsDirectory();
    final bookDir = Directory(path.join(appDir.path, 'books', bookId));
    await bookDir.create(recursive: true);
    
    // Copy the EPUB file
    final savedPath = path.join(bookDir.path, 'book.epub');
    await epubFile.copy(savedPath);
    
    // Extract cover from images (first image or epub.CoverImage if available)
    String? coverPath;
    final images = epub.Content?.Images;
    if (images != null && images.isNotEmpty) {
      final coverImage = images.values.first;
      coverPath = path.join(bookDir.path, 'cover.jpg');
      await File(coverPath).writeAsBytes(coverImage.Content!);
    }

    return Book(
      id: bookId,
      filePath: savedPath,
      title: epub.Title ?? 'Unknown Title',
      author: epub.Author,
      coverPath: coverPath,
      addedAt: DateTime.now(),
    );
  }

  Future<List<Chapter>> getChapters(String epubPath) async {
    try {
      final bytes = await File(epubPath).readAsBytes();
      final epub = await EpubReader.readBook(bytes);
      
      // Simple fallback - just use chapter count
      final chapters = <Chapter>[];
      final chapterCount = epub.Chapters?.length ?? 1;
      
      for (int i = 0; i < chapterCount; i++) {
        chapters.add(Chapter(
          id: 'ch_$i',
          title: 'Chapter ${i + 1}',
          href: '',
          index: i,
          subChapters: [],
        ));
      }
      return chapters;
    } catch (e) {
      print('⚠️ Chapters parse failed: $e');
      // Return dummy chapters so UI doesn't break
      return [
        Chapter(id: 'ch_0', title: 'Chapter 1', href: '', index: 0, subChapters: []),
      ];
    }
  }


  /// Extract EPUB to a temporary directory for WebView rendering
  Future<String> extractEpubForRendering(String epubPath) async {
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(path.join(tempDir.path, 'epub_render_${DateTime.now().millisecondsSinceEpoch}'));
    
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    final bytes = await File(epubPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filePath = path.join(extractDir.path, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }

    return extractDir.path;
  }

  /// Delete book files
  Future<void> deleteBook(String bookId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final bookDir = Directory(path.join(appDir.path, 'books', bookId));
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }
  }

  /// Get total word count estimate for reading time calculation
  Future<double> estimateWordCount(String epubPath) async {
    final bytes = await File(epubPath).readAsBytes();
    final epub = await EpubReader.readBook(bytes);
    
    double totalWords = 0.0;
    final content = epub.Content;
    
    if (content?.Html != null) {
      for (final html in content!.Html!.values) {
        if (html.Content != null) {
          // Strip HTML tags and count words
          final text = html.Content!.replaceAll(RegExp(r'<[^>]*>'), ' ');
          final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
          totalWords += words.length;
        }
      }
    }
    
    return totalWords;
  }

  /// Calculate reading time in minutes (average 200 wpm)
  int calculateReadingTime(int wordCount, {int wordsPerMinute = 200}) {
    return (wordCount / wordsPerMinute).ceil();
  }
}