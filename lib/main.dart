import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:epub_view/epub_view.dart';
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

  // 🔹 Load saved books
  Future<void> loadBooksFromStorage() async {
    final pref = await SharedPreferences.getInstance();
    books = pref.getStringList('books') ?? [];
    setState(() {});
  }

  // 🔹 Pick + save epub
  Future<void> pickEpubFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);

      final dir = await getApplicationDocumentsDirectory();

      final savedFile = await file.copy(
        '${dir.path}/${result.files.single.name}',
      );

      print("Saved to ${savedFile.path}");

      await saveFilePath(savedFile.path);

      await loadBooksFromStorage();
    }
  }

  // 🔹 Save path
  Future<void> saveFilePath(String path) async {
    final pref = await SharedPreferences.getInstance();

    List<String> books = pref.getStringList('books') ?? [];
    books.add(path);

    await pref.setStringList('books', books);
  }

  // 🔹 Delete book
  Future<void> deleteBook(int index) async {
    final pref = await SharedPreferences.getInstance();

    books.removeAt(index);

    await pref.setStringList('books', books);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Library"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickEpubFile,
        child: const Icon(Icons.add),
      ),
      body: books.isEmpty
          ? const Center(child: Text("No books yet"))
          : ListView.builder(
              itemCount: books.length,
              itemBuilder: (context, index) {
                String path = books[index];
                String fileName = path.split('/').last;

                return ListTile(
                  title: Text(fileName),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => deleteBook(index),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReaderPage(path: path),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class ReaderPage extends StatelessWidget {
  final String path;

  const ReaderPage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reader")),
      body: EpubView(
        controller: EpubController(
          document: EpubDocument.openFile(File(path)),
        ),
      ),
    );
  }
}
