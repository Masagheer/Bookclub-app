// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/book.dart';
import '../models/highlight.dart';
import '../models/comment.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'bookclub.db';
  static const int _dbVersion = 1;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        filePath TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        coverPath TEXT,
        addedAt TEXT NOT NULL,
        lastReadAt TEXT,
        lastCfi TEXT,
        progress REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE highlights (
        id TEXT PRIMARY KEY,
        bookId TEXT NOT NULL,
        cfi TEXT NOT NULL,
        text TEXT NOT NULL,
        note TEXT,
        color INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        userId TEXT NOT NULL,
        commentCount INTEGER DEFAULT 0,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE comments (
        id TEXT PRIMARY KEY,
        highlightId TEXT NOT NULL,
        bookId TEXT NOT NULL,
        userId TEXT NOT NULL,
        userName TEXT NOT NULL,
        userAvatar TEXT,
        body TEXT NOT NULL,
        parentId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        FOREIGN KEY (highlightId) REFERENCES highlights(id) ON DELETE CASCADE,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        bookId TEXT NOT NULL,
        cfi TEXT NOT NULL,
        title TEXT,
        excerpt TEXT,
        chapterIndex INTEGER,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_highlights_bookId ON highlights(bookId)');
    await db.execute('CREATE INDEX idx_comments_highlightId ON comments(highlightId)');
    await db.execute('CREATE INDEX idx_bookmarks_bookId ON bookmarks(bookId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
  }

  // Book operations
  Future<void> insertBook(Book book) async {
    final db = await database;
    await db.insert('books', book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateBook(Book book) async {
    final db = await database;
    await db.update('books', book.toMap(), where: 'id = ?', whereArgs: [book.id]);
  }

  Future<void> deleteBook(String id) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final maps = await db.query('books', orderBy: 'lastReadAt DESC, addedAt DESC');
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  Future<Book?> getBook(String id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<void> updateReadingProgress(String bookId, String cfi, double progress) async {
    final db = await database;
    await db.update(
      'books',
      {
        'lastCfi': cfi,
        'progress': progress,
        'lastReadAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // Highlight operations
  Future<void> insertHighlight(Highlight highlight) async {
    final db = await database;
    await db.insert('highlights', highlight.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateHighlight(Highlight highlight) async {
    final db = await database;
    await db.update('highlights', highlight.toMap(), where: 'id = ?', whereArgs: [highlight.id]);
  }

  Future<void> deleteHighlight(String id) async {
    final db = await database;
    await db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Highlight>> getHighlightsForBook(String bookId) async {
    final db = await database;
    final maps = await db.query(
      'highlights',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((map) => Highlight.fromMap(map)).toList();
  }

  Future<Highlight?> getHighlightByCfi(String bookId, String cfi) async {
    final db = await database;
    final maps = await db.query(
      'highlights',
      where: 'bookId = ? AND cfi = ?',
      whereArgs: [bookId, cfi],
    );
    if (maps.isEmpty) return null;
    return Highlight.fromMap(maps.first);
  }

  Future<void> updateHighlightCommentCount(String highlightId, int delta) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE highlights 
      SET commentCount = commentCount + ? 
      WHERE id = ?
    ''', [delta, highlightId]);
  }

  // Comment operations
  Future<void> insertComment(Comment comment) async {
    final db = await database;
    await db.insert('comments', comment.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await updateHighlightCommentCount(comment.highlightId, 1);
  }

  Future<void> deleteComment(String id, String highlightId) async {
    final db = await database;
    await db.delete('comments', where: 'id = ?', whereArgs: [id]);
    await updateHighlightCommentCount(highlightId, -1);
  }

  Future<List<Comment>> getCommentsForHighlight(String highlightId) async {
    final db = await database;
    final maps = await db.query(
      'comments',
      where: 'highlightId = ? AND parentId IS NULL',
      whereArgs: [highlightId],
      orderBy: 'createdAt ASC',
    );
    
    List<Comment> comments = [];
    for (final map in maps) {
      final comment = Comment.fromMap(map);
      final replies = await _getReplies(highlightId, comment.id);
      comments.add(comment.copyWith(replies: replies));
    }
    return comments;
  }

  Future<List<Comment>> _getReplies(String highlightId, String parentId) async {
    final db = await database;
    final maps = await db.query(
      'comments',
      where: 'highlightId = ? AND parentId = ?',
      whereArgs: [highlightId, parentId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((map) => Comment.fromMap(map)).toList();
  }

  // Bookmark operations
  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBookmark(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> getBookmarksForBook(String bookId) async {
    final db = await database;
    final maps = await db.query(
      'bookmarks',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((map) => Bookmark.fromMap(map)).toList();
  }

  Future<Bookmark?> getBookmarkByCfi(String bookId, String cfi) async {
    final db = await database;
    final maps = await db.query(
      'bookmarks',
      where: 'bookId = ? AND cfi = ?',
      whereArgs: [bookId, cfi],
    );
    if (maps.isEmpty) return null;
    return Bookmark.fromMap(maps.first);
  }

  // Settings operations
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  Future<ReadingSettings> getReadingSettings() async {
    final json = await getSetting('readingSettings');
    if (json == null) return const ReadingSettings();
    return ReadingSettings.fromJson(json);
  }

  Future<void> saveReadingSettings(ReadingSettings settings) async {
    await saveSetting('readingSettings', settings.toJson());
  }
}