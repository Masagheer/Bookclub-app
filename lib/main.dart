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

class _HomePageState extends State<HomePage>{
  @override
  Widget build(BuildContext content){
    return Scaffold(
      appBar: AppBar(title: const Text("Epub shit")),
      floatingActionButton: FloatingActionButton(onPressed: uploadEpub, child: const Icon(Icons.add),),
      body: Center(
        child: books.isEmpty ? 
        const Text("No books yet") : 
        ListView.builder(
          itemCount: books.length,
          itemBuilder: (context, index) {
            String path = books[index];
            String fileName = path.split('/').last;
            return ListTile(
              title: Text(fileName),
              trailing:IconButton(onPressed: () => deleteBook(index), icon: const Icon(Icons.delete)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(path: path))),
            );
          }),
      )
    );
  }

  List<String> books = [];

  void initiateState(){
    super.initState();
    loadBooksFromStorage();
  }

  Future<void> loadBooksFromStorage() async{
    final pref = await SharedPreferences.getInstance();
    books = pref.getStringList('books') ?? [];
    setState(() {});
  }

  // upload and save epub
  void uploadEpub() async{
    // when you clicj on button, open file picker and let user select an epub file
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['epub']);
    
    // result is the file that the user picked 
    if (result != null){
      // get the path that the user picked
      File file = File(result.files.single.path!);
      // find a safe directory to save the file to
      final dir = await getApplicationCacheDirectory();
      // save the file to the safe directory
      final savedFile = await file.copy('${dir.path}/${result.files.single.name}');
      // make the saved file appear in the homepage.
      await savedFilePath(savedFile.path);
      await loadBooksFromStorage();
    }
  }

  // save path
  Future<void> savedFilePath(String path) async{
    final pref = await SharedPreferences.getInstance();
    List<String> books = pref.getStringList('books') ?? [];
    books.add(path);

    await pref.setStringList('books', books);
  }

  // delete book
  void deleteBook(int index) async{
    final pref = await SharedPreferences.getInstance();
    books.removeAt(index);
    await pref.setStringList('books', books);
    setState(() {});
  }
}

class ReaderPage extends StatefulWidget{
  final String path;
  
  const ReaderPage({super.key, required this.path});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
  // Widget build(BuildContext context){
  //   return Scaffold(
  //     appBar: AppBar(title: Text("Reading")),
  //     body: EpubView(controller: EpubController(document: EpubDocument.openFile(File(path)))),
  //   );
  // }
}

class _ReaderPageState extends State<ReaderPage> {
  final EpubController _epubController = EpubController();
  String? _lastSelectionCfi;
  double _progress = 0.0; // 0–1

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${(_progress * 100).toStringAsFixed(1)}%"),
      ),
      body: SafeArea(
        child: EpubViewer(
          epubSource: EpubSource.fromFile(File(widget.path)),
          epubController: _epubController,
          displaySettings: EpubDisplaySettings(
            flow: EpubFlow.paginated,
            snap: true,
            theme: EpubTheme.dark(), // or light(), or custom later
          ),
          onRelocated: (location) {
            // location.progress is 0..1
            setState(() => _progress = location.progress);
          },
          onTextSelected: (selection) {
            // save selection CFI so we know *where* the text lives
            _lastSelectionCfi = selection.selectionCfi;
          },
          selectionContextMenu: _buildContextMenu(),
        ),
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
            if (_lastSelectionCfi != null) {
              _epubController.addHighlight(cfi: _lastSelectionCfi!);
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
      settings: ContextMenuSettings(
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
              // TODO: save to Firestore/your backend here
              // document example:
              // {
              //   bookId,
              //   groupId,
              //   cfi,
              //   textSnippet,
              //   body: commentText,
              //   userId,
              //   createdAt,
              //   parentId: null (for root comment)
              // }
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