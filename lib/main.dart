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
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ReaderPage(path: path))),
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

class ReaderPage extends StatelessWidget{
  final String path;
  
  const ReaderPage({super.key, required this.path});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text("Reading")),
      body: EpubView(controller: EpubController(document: EpubDocument.openFile(File(path)))),
    );
  }
}