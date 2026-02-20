// lib/providers/reader_state.dart
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/highlight.dart';
import '../models/comment.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/reading_settings.dart';
import '../services/database_service.dart';
import '../services/epub_service.dart';

class ReaderState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final EpubService _epubService = EpubService();
  
  // Current user (simplified - integrate with your auth system)
  String _currentUserId = 'local_user';
  String _currentUserName = 'You';
  
  // Book state
  Book? _currentBook;
  List<Chapter> _chapters = [];
  List<Highlight> _highlights = [];
  List<Bookmark> _bookmarks = [];
  
  // Reading state
  String? _currentCfi;
  double _progress = 0.0;
  int _currentPage = 0;
  int _totalPages = 0;
  int? _estimatedReadingTimeLeft;
  
  // Settings
  ReadingSettings _settings = const ReadingSettings();
  
  // Selection state
  String? _selectedCfi;
  String? _selectedText;
  
  // Loading states
  bool _isLoading = false;
  String? _error;

  // Getters
  Book? get currentBook => _currentBook;
  List<Chapter> get chapters => _chapters;
  List<Highlight> get highlights => _highlights;
  List<Bookmark> get bookmarks => _bookmarks;
  String? get currentCfi => _currentCfi;
  double get progress => _progress;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int? get estimatedReadingTimeLeft => _estimatedReadingTimeLeft;
  ReadingSettings get settings => _settings;
  String? get selectedCfi => _selectedCfi;
  String? get selectedText => _selectedText;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentUserId => _currentUserId;
  String get currentUserName => _currentUserName;

  // Initialize reader with a book
  Future<void> loadBook(Book book) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentBook = book;
      
      // Load chapters
      _chapters = await _epubService.getChapters(book.filePath);
      
      // Load highlights and bookmarks
      _highlights = await _db.getHighlightsForBook(book.id);
      _bookmarks = await _db.getBookmarksForBook(book.id);
      
      // Load settings
      _settings = await _db.getReadingSettings();
      
      // Set initial position
      _currentCfi = book.lastCfi;
      _progress = book.progress;
      
      // Calculate reading time
      final wordCount = await _epubService.estimateWordCount(book.filePath);
      final totalMinutes = _epubService.calculateReadingTime(wordCount.toInt());
      _estimatedReadingTimeLeft = ((1 - _progress) * totalMinutes).ceil();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update reading position
  Future<void> updatePosition(String cfi, double progress, int currentPage, int totalPages) async {
    _currentCfi = cfi;
    _progress = progress;
    _currentPage = currentPage;
    _totalPages = totalPages;
    
    // Update reading time estimate
    if (_estimatedReadingTimeLeft != null) {
      final totalMinutes = _estimatedReadingTimeLeft! / (1 - _currentBook!.progress);
      _estimatedReadingTimeLeft = ((1 - progress) * totalMinutes).ceil();
    }
    
    // Save to database
    if (_currentBook != null) {
      await _db.updateReadingProgress(_currentBook!.id, cfi, progress);
      _currentBook = _currentBook!.copyWith(
        lastCfi: cfi,
        progress: progress,
        lastReadAt: DateTime.now(),
      );
    }
    
    notifyListeners();
  }

  // Selection handling
  void setSelection(String? cfi, String? text) {
    _selectedCfi = cfi;
    _selectedText = text;
    notifyListeners();
  }

  void clearSelection() {
    _selectedCfi = null;
    _selectedText = null;
    notifyListeners();
  }

  // Highlight operations
  Future<Highlight> addHighlight({
    required String cfi,
    required String text,
    HighlightColor color = HighlightColor.yellow,
    String? note,
  }) async {
    final highlight = Highlight(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: _currentBook!.id,
      cfi: cfi,
      text: text,
      color: color,
      note: note,
      createdAt: DateTime.now(),
      userId: _currentUserId,
    );
    
    await _db.insertHighlight(highlight);
    _highlights.insert(0, highlight);
    notifyListeners();
    
    return highlight;
  }

  Future<void> updateHighlight(Highlight highlight) async {
    final updated = highlight.copyWith(updatedAt: DateTime.now());
    await _db.updateHighlight(updated);
    
    final index = _highlights.indexWhere((h) => h.id == highlight.id);
    if (index != -1) {
      _highlights[index] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteHighlight(String highlightId) async {
    await _db.deleteHighlight(highlightId);
    _highlights.removeWhere((h) => h.id == highlightId);
    notifyListeners();
  }

  Highlight? getHighlightByCfi(String cfi) {
    try {
      return _highlights.firstWhere((h) => h.cfi == cfi);
    } catch (e) {
      return null;
    }
  }

  // Bookmark operations
  Future<Bookmark> addBookmark({String? title, String? excerpt}) async {
    final bookmark = Bookmark(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: _currentBook!.id,
      cfi: _currentCfi!,
      title: title,
      excerpt: excerpt,
      createdAt: DateTime.now(),
    );
    
    await _db.insertBookmark(bookmark);
    _bookmarks.insert(0, bookmark);
    notifyListeners();
    
    return bookmark;
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await _db.deleteBookmark(bookmarkId);
    _bookmarks.removeWhere((b) => b.id == bookmarkId);
    notifyListeners();
  }

  bool isCurrentPageBookmarked() {
    if (_currentCfi == null) return false;
    return _bookmarks.any((b) => b.cfi == _currentCfi);
  }

  // Comment operations
  Future<Comment> addComment({
    required String highlightId,
    required String body,
    String? parentId,
  }) async {
    final comment = Comment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      highlightId: highlightId,
      bookId: _currentBook!.id,
      userId: _currentUserId,
      userName: _currentUserName,
      body: body,
      parentId: parentId,
      createdAt: DateTime.now(),
    );
    
    await _db.insertComment(comment);
    
    // Update highlight comment count
    final highlightIndex = _highlights.indexWhere((h) => h.id == highlightId);
    if (highlightIndex != -1) {
      _highlights[highlightIndex] = _highlights[highlightIndex].copyWith(
        commentCount: _highlights[highlightIndex].commentCount + 1,
      );
    }
    
    notifyListeners();
    return comment;
  }

  Future<List<Comment>> getCommentsForHighlight(String highlightId) async {
    return await _db.getCommentsForHighlight(highlightId);
  }

  // Settings operations
  Future<void> updateSettings(ReadingSettings newSettings) async {
    _settings = newSettings;
    await _db.saveReadingSettings(newSettings);
    notifyListeners();
  }

  // Search (returns list of CFI locations)
  // This would need to be implemented with the WebView's search functionality
  
  // Cleanup
  void dispose() {
    _currentBook = null;
    _chapters = [];
    _highlights = [];
    _bookmarks = [];
    super.dispose();
  }
}