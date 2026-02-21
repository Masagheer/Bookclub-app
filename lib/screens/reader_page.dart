import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:epub_view/epub_view.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'dart:io';

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

class HomePage extends StatefulWidget{
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
      appBar: AppBar(title: const Text("Epub shit")),
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
    final list = pref.getStringList('books') ?? [];
    list.add(path);
    await pref.setStringList('books', list);
  }

  Future<void> uploadEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
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
  late EpubController _epubController;
  String? _lastSelectionCfi;
  double _progress = 0.0;
  String? _initialCfi; // last saved position

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();

    // restore last position (CFI) for this book
    _initialCfi = prefs.getString('lastCfi_${widget.path}');

    _epubController = EpubController();

    setState(() {}); // trigger rebuild so EpubViewer has controller + initialCfi
  }

  Future<void> _saveLastCfi(String cfi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastCfi_${widget.path}', cfi);
  }

  Future<void> _saveHighlight(String cfi) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'highlights_${widget.path}';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(cfi)) {
      list.add(cfi);
      await prefs.setStringList(key, list);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Until controller is ready, show loader
    if (!mounted || _initialCfi == null && _epubController == null) {
      // small guard; if needed, refine
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${(_progress * 100).toStringAsFixed(1)}%"),
      ),
      body: SafeArea(
        child: _buildViewer(),
      ),
    );
  }

  Widget _buildViewer() {
    // If _epubController isn’t initialized yet, show loader
    if (!(_epubController is EpubController)) {
      return const Center(child: CircularProgressIndicator());
    }

    return EpubViewer(
      initialCfi: _initialCfi,
      epubSource: EpubSource.fromFile(File(widget.path)),
      epubController: _epubController,
      displaySettings: const EpubDisplaySettings(
        flow: EpubFlow.paginated,
        snap: true,
      ),
      onRelocated: (location) {
        setState(() => _progress = location.progress);
        if (location.cfi != null) {
          _saveLastCfi(location.cfi!);
        }
      },
      onTextSelected: (selection) {
        _lastSelectionCfi = selection.selectionCfi;
      },
      selectionContextMenu: _buildContextMenu(),
    );
  }

  ContextMenu _buildContextMenu() {
    return ContextMenu(
      menuItems: [
        ContextMenuItem(
          id: 1,
          title: "Highlight",
          action: () async {
            if (_lastSelectionCfi != null) {
              _epubController.addHighlight(cfi: _lastSelectionCfi!);
              await _saveHighlight(_lastSelectionCfi!);
            }
          },
        ),
        ContextMenuItem(
          id: 2,
          title: "Comment",
          action: () async {
            if (_lastSelectionCfi == null) return;
            final text = await _epubController.extractText(
              startCfi: _lastSelectionCfi!,
              endCfi: _lastSelectionCfi!,
            );
            _openCommentSheet(
              context: context,
              cfi: _lastSelectionCfi!,
              textSnippet: (text ?? "").toString(),
            );
          },
        ),
      ],
      settings: const ContextMenuSettings(
        hideDefaultSystemContextMenuItems: true,
      ),
    );
  }

  void _openCommentSheet({
    required BuildContext context,
    required String cfi,
    required String textSnippet,
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
            onSubmitted: (commentText) async {
              // Later: send to backend with bookId + groupId + userId
              // For now just print:
              debugPrint("Comment on $cfi: $commentText");
              Navigator.pop(ctx);
            },
          ),
        );
      },
    );
  }
}

class _CommentComposer extends StatefulWidget {
  final String cfi;
  final String textSnippet;
  final ValueChanged<String> onSubmitted;

  const _CommentComposer({
    required this.cfi,
    required this.textSnippet,
    required this.onSubmitted,
  });

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Selected text:",
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Text(
          widget.textSnippet,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 3,
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
            child: const Text("Post comment"),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}