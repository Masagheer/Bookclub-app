import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookclub Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromRGBO(231, 66, 101, 1),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> books = [];

  @override
  void initState() {
    super.initState();
    loadBooksFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Deer Bookclub")),
      floatingActionButton: FloatingActionButton(
        onPressed: uploadEpub,
        child: const Icon(Icons.add),
      ),
      body: Center(
        child: books.isEmpty
            ? const Text("No books yet")
            : ListView.builder(
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final path = books[index];
                  final fileName = path.split('/').last;
                  return ListTile(
                    title: Text(fileName),
                    trailing: IconButton(
                      onPressed: () => deleteBook(index),
                      icon: const Icon(Icons.delete),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReaderPage(path: path),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> loadBooksFromStorage() async {
    final pref = await SharedPreferences.getInstance();
    books = pref.getStringList('books') ?? [];
    setState(() {});
  }

  Future<void> savedFilePath(String path) async {
    final pref = await SharedPreferences.getInstance();
    List<String> books = pref.getStringList('books') ?? [];
    books.add(path);
    await pref.setStringList('books', books);
  }

  Future<void> uploadEpub() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      final dir = await getApplicationCacheDirectory();
      final savedFile = await file.copy('${dir.path}/${result.files.single.name}');
      await savedFilePath(savedFile.path);
      await loadBooksFromStorage();
    }
  }

  Future<void> deleteBook(int index) async {
    final pref = await SharedPreferences.getInstance();
    books.removeAt(index);
    await pref.setStringList('books', books);
    setState(() {});
  }
}

class ReaderPage extends StatefulWidget {
  final String path;

  const ReaderPage({super.key, required this.path});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  EpubController? _epubController;
  String? _lastSelectionCfi;
  String? _initialLocation;
  double _progress = 0.0;
  List<String> _savedHighlights = [];
  List<Map<String, dynamic>> _savedComments = [];
  bool _isLoading = true;
  double _fontSize = 16.0;
  int _themeIndex = 0; // 0 = light, 1 = dark, 2 = sepia
  int _viewerVersion = 0;
  bool _showViewer = true;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();

    _progress = prefs.getDouble('lastProgress_$bookId') ?? 0.0;
    _initialLocation = prefs.getString('lastLocation_$bookId'); // Add this line
    _savedHighlights = prefs.getStringList('highlights_$bookId') ?? [];
    _fontSize = prefs.getDouble('fontSize_$bookId') ?? 16.0; // Add this line
    _themeIndex = prefs.getInt('theme_$bookId') ?? 0;

    // Load comments
    final commentsJson = prefs.getStringList('comments_$bookId') ?? [];
    _savedComments = commentsJson
        .map((json) => jsonDecode(json) as Map<String, dynamic>)
        .toList();

    _epubController = EpubController();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _increaseFontSize() {
    setState(() {
      if (_fontSize < 32.0) {
        _fontSize += 2.0;
        _saveFontSize();
        _updateEpubFontSize();
      }
    });
  }

  void _decreaseFontSize() {
    setState(() {
      if (_fontSize > 10.0) {
        _fontSize -= 2.0;
        _saveFontSize();
        _updateEpubFontSize();
      }
    });
  }

  void _resetFontSize() {
    setState(() {
      _fontSize = 16.0;
      _saveFontSize();
      // _updateEpubFontSize();
    });
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();
    await prefs.setDouble('fontSize_$bookId', _fontSize);
  }

  void _updateEpubFontSize() {
    // _epubController?.evaluateJavascript(
    //   "document.documentElement.style.fontSize = '${_fontSize}px';",
    // );
  }

  Future<void> _saveProgress(String? cfi) async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();
    await prefs.setDouble('lastProgress_$bookId', _progress);
    if (cfi != null) {
      await prefs.setString('lastLocation_$bookId', cfi);
    }
  }

  Future<void> _saveHighlight(String cfi) async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();
    final highlights = prefs.getStringList('highlights_$bookId') ?? [];
    if (!highlights.contains(cfi)) {
      highlights.add(cfi);
      await prefs.setStringList('highlights_$bookId', highlights);
      setState(() {
        _savedHighlights = highlights;
      });
    }
  }

  Future<void> _saveComment({
    required String cfi,
    required String textSnippet,
    required String comment,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();

    final newComment = {
      'cfi': cfi,
      'textSnippet': textSnippet,
      'comment': comment,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _savedComments.add(newComment);

    final commentsJson = _savedComments.map((c) => jsonEncode(c)).toList();
    await prefs.setStringList('comments_$bookId', commentsJson);

    // Also save as highlight so it appears highlighted
    await _saveHighlight(cfi);

    // Apply the highlight immediately
    if (_epubController != null) {
      _epubController!.addHighlight(cfi: cfi, color: Colors.orange);
    }

    setState(() {});
  }

  Future<void> _applyHighlights() async {
    if (_epubController == null) return;

    await Future.delayed(const Duration(milliseconds: 300));

    // Get CFIs that have comments
    final commentCfis = _savedComments.map((c) => c['cfi'] as String).toSet();

    for (final cfi in _savedHighlights) {
      try {
        // Orange for comments, yellow for regular highlights
        final color = commentCfis.contains(cfi) ? Colors.orange : Colors.yellow;
        _epubController!.addHighlight(cfi: cfi, color: color);
      } catch (e) {
        debugPrint('Failed to apply highlight at $cfi: $e');
      }
    }
  }

  Map<String, dynamic>? _findCommentByCfi(String cfi) {
    try {
      return _savedComments.firstWhere((c) => c['cfi'] == cfi);
    } catch (e) {
      return null;
    }
  }

  EpubTheme _getTheme() {
    switch (_themeIndex) {
      case 1:
        return EpubTheme.dark();
      default:
        return EpubTheme.light();
    }
  }

  Future<void> _switchTheme() async {
    if (_epubController == null) return;

    final currentCfi = _initialLocation;

    setState(() {
      _themeIndex = (_themeIndex + 1) % 2;
      _showViewer = false; // remove viewer
    });

    await Future.delayed(const Duration(milliseconds: 50));

    setState(() {
      _initialLocation = currentCfi;
      _showViewer = true; // rebuild viewer
    });
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final bookId = widget.path.hashCode.toString();
    await prefs.setInt('theme_$bookId', _themeIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${(_progress * 100).toStringAsFixed(1)}%"),
        actions: [
          IconButton(
            icon: const Icon(Icons.comment),
            onPressed: () => _showAllComments(context),
          ),
          IconButton(
            icon: Icon(Icons.text_decrease),
            onPressed: _decreaseFontSize,
            tooltip: 'Decrease Font Size',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Text(
                '${_fontSize.toStringAsFixed(0)}px',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.text_increase),
            onPressed: _increaseFontSize,
            tooltip: 'Increase Font Size',
          ),
          IconButton(
            icon: const Icon(Icons.palette),
            onPressed: _switchTheme,
            tooltip: "Switch Theme",
          ),
          // IconButton(
          //   icon: Icon(Icons.refresh),
          //   onPressed: _resetFontSize,
          //   tooltip: 'Reset Font Size',
          // ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _showViewer ? EpubViewer(
              key: ValueKey(_fontSize), // 👈 ADD THIS
              initialCfi: _initialLocation,
              epubSource: EpubSource.fromFile(File(widget.path)),
              epubController: _epubController!,
              displaySettings: EpubDisplaySettings(
                flow: EpubFlow.paginated,
                snap: true,
                theme:  _getTheme(),
                fontSize: _fontSize.toInt(),
              ),
              onChaptersLoaded: (chapters) {
                _applyHighlights();
                _updateEpubFontSize(); // Apply font size when chapters load
              },
              onRelocated: (location) {
                _initialLocation = location.startCfi; // 👈 store live position
                setState(() => _progress = location.progress);
                _saveProgress(location.startCfi);
              },
              onTextSelected: (selection) {
                _lastSelectionCfi = selection.selectionCfi;
              },
              selectionContextMenu: _buildContextMenu(),
            )
            : const SizedBox.shrink(),
      ),
    );
  }

  ContextMenu _buildContextMenu() {
    return ContextMenu(
      menuItems: [
        ContextMenuItem(
          id: 1,
          title: "Highlight",
          action: () async {
            if (_lastSelectionCfi != null && _epubController != null) {
              _epubController!.addHighlight(
                cfi: _lastSelectionCfi!,
                color: Colors.yellow,
              );
              await _saveHighlight(_lastSelectionCfi!);
            }
          },
        ),
        ContextMenuItem(
          id: 2,
          title: "Comment",
          action: () async {
            if (_lastSelectionCfi == null || _epubController == null) return;
            
            String textSnippet = "Selected text";
            try {
              final text = await _epubController!.extractText(
                startCfi: _lastSelectionCfi!,
                endCfi: _lastSelectionCfi!,
              );
              if (text != null && text.toString().isNotEmpty) {
                textSnippet = text.toString();
              }
            } catch (e) {
              debugPrint('Could not extract text: $e');
            }
            
            _openCommentSheet(
              context: context,
              cfi: _lastSelectionCfi!,
              textSnippet: textSnippet,
            );
          },
        ),
      ],
      settings: ContextMenuSettings(
        hideDefaultSystemContextMenuItems: true,
      ),
    );
  }

  void _openCommentSheet({
    required BuildContext context,
    required String cfi,
    required String textSnippet,
    Map<String, dynamic>? existingComment,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: _CommentComposer(
            cfi: cfi,
            textSnippet: textSnippet,
            existingComment: existingComment?['comment'],
            onSubmitted: (commentText) async {
              await _saveComment(
                cfi: cfi,
                textSnippet: textSnippet,
                comment: commentText,
              );
              Navigator.pop(ctx);
            },
          ),
        );
      },
    );
  }

  void _showAllComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            if (_savedComments.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    "No comments yet.\nSelect text and tap 'Comment' to add one.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _savedComments.length,
              itemBuilder: (_, index) {
                final comment = _savedComments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      // Navigate to the comment location
                      _epubController?.display(cfi: comment['cfi']);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              comment['textSnippet'] ?? '',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            comment['comment'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(comment['createdAt']),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}

class _CommentComposer extends StatefulWidget {
  final String cfi;
  final String textSnippet;
  final String? existingComment;
  final ValueChanged<String> onSubmitted;

  const _CommentComposer({
    required this.cfi,
    required this.textSnippet,
    this.existingComment,
    required this.onSubmitted,
  });

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingComment != null) {
      _controller.text = widget.existingComment!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Selected text:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.textSnippet,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Write your comment…",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: () {
              if (_controller.text.trim().isEmpty) return;
              widget.onSubmitted(_controller.text.trim());
            },
            child: Text(widget.existingComment != null ? "Update" : "Post comment"),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  } 
}

