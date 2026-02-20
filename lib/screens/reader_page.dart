// lib/screens/reader_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'dart:io';
import '../models/book.dart';
import '../models/highlight.dart';
import '../models/reading_settings.dart';
import '../providers/reader_state.dart';
import '../services/epub_service.dart';
import './reader_drawer.dart';
import '../widgets/reader/theme_settings_sheet.dart';
import '../widgets/comments/comment_sheet.dart';
import 'package:epubx/epubx.dart';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';

class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final EpubService _epubService = EpubService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>(); // ADD THIS
  InAppWebViewController? _webViewController;
  String? _extractedPath;
  bool _isReady = false;
  bool _showControls = true;
  
  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  int _currentSearchIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeReader();
  }

  Future<void> _initializeReader() async {
    final readerState = context.read<ReaderState>();
    await readerState.loadBook(widget.book);
    
    // Extract EPUB for rendering
    _extractedPath = await _epubService.extractEpubForRendering(widget.book.filePath);
    
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Cleanup extracted files
    if (_extractedPath != null) {
      Directory(_extractedPath!).delete(recursive: true).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, readerState, child) {
        if (readerState.isLoading || _extractedPath == null) {
          return Scaffold(
            backgroundColor: readerState.settings.theme.backgroundColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          key: _scaffoldKey,  // ADD THIS
          backgroundColor: readerState.settings.theme.backgroundColor,
          drawer: ReaderDrawer(
            onChapterSelected: _navigateToChapter,
            onHighlightSelected: _navigateToHighlight,
            onBookmarkSelected: _navigateToBookmark,
          ),
          body: Stack(
            children: [
              // EPUB WebView
              GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: _buildWebView(readerState),
              ),
              
              // Top controls
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildTopBar(readerState),
              ),
              
              // Bottom controls
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildBottomBar(readerState),
              ),
              
              // Search overlay
              if (_isSearching) _buildSearchOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebView(ReaderState readerState) {
    return FutureBuilder<String?>(
      future: _loadBookContent(widget.book.filePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final content = snapshot.data ?? '<h2>No content found</h2>';
        final fullHtml = _fixEpubHtml(content, widget.book.title);
        
        return InAppWebView(
          initialData: InAppWebViewInitialData(
            data: fullHtml,
            // NO baseUrl = fixes FormatException
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            verticalScrollBarEnabled: true,
            allowFileAccess: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            _setupJavaScriptHandlers(controller);
          },
          onLoadStop: (controller, url) {
            print('✅ WebView loaded content: ${content.length} chars');
          },
        );
      },
    );
  }

  // Future<String?> _loadBookContent(String epubPath) async {
  //   try {
  //     print('📖 Loading EPUB: $epubPath');
  //     final bytes = await File(epubPath).readAsBytes();
  //     final epub = await EpubReader.readBook(bytes);
      
  //     print('✅ Title: ${epub.Title}');
  //     print('✅ epubx Chapters: ${epub.Chapters?.length ?? 0}');
      
  //     // Check epubx first (protect working books)
  //     bool useEpubx = false;
  //     for (final chapter in epub.Chapters ?? []) {
  //       final contentLength = (chapter.HtmlContent ?? '').length;
  //       if (contentLength > 1500) {
  //         useEpubx = true;
  //         print('✅ epubx Chapter "${chapter.Title}" (${contentLength} chars) - USING EPUBX');
  //         break;
  //       }
  //     }
      
  //     if (useEpubx) {
  //       print('🎉 Using epubx (working book)');
  //       return _buildEpubxHtml(epub);
  //     }
      
  //     // ZIP fallback - safer scanning
  //     print('🔄 ZIP fallback...');
  //     final archive = ZipDecoder().decodeBytes(bytes);
  //     print('📦 ZIP files: ${archive.length}');
      
  //     List<ArchiveFile> contentFiles = [];
  //     for (final file in archive) {
  //       if (file.isFile) {
  //         String fileName = file.name.toLowerCase();
  //         if ((fileName.endsWith('.html') || fileName.endsWith('.xhtml')) && 
  //             file.content.length > 500) {
  //           try {
  //             String preview = utf8.decode(file.content).substring(0, 150);
  //             print('📄 ${file.name.padRight(40)} | ${file.content.length} chars');
  //             contentFiles.add(file);
  //           } catch (e) {
  //             print('⚠️ Skip ${file.name}: $e');
  //           }
  //         }
  //       }
  //     }
      
  //     print('✅ Found ${contentFiles.length} content files');
      
  //     if (contentFiles.isEmpty) {
  //       print('⚠️ No ZIP content - using epubx');
  //       return _buildEpubxHtml(epub);
  //     }
      
  //     // Build HTML (safer regex)
  //     StringBuffer html = StringBuffer();
  //     html.writeln('<!DOCTYPE html><html><head>');
  //     html.writeln('<meta charset="UTF-8">');
  //     html.writeln('<style>');
  //     html.writeln('body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;background:white;color:#333;}');
  //     html.writeln('h2{color:#2c5aa0;border-bottom:2px solid #eee;padding-bottom:10px;}');
  //     html.writeln('.debug{background:#f0f8ff;padding:15px;border-left:4px solid #007acc;font-size:14px;margin:20px 0;}');
  //     html.writeln('</style></head><body>');
      
  //     for (int i = 0; i < (contentFiles.length > 5 ? 5 : contentFiles.length); i++) {
  //       final file = contentFiles[i];
  //       String content = utf8.decode(file.content);
        
  //       html.writeln('<div style="margin-bottom:60px;padding-bottom:40px;border-bottom:2px solid #eee;">');
  //       html.writeln('<h2>📖 ${file.name.split('/').last}</h2>');
        
  //       html.writeln('<div class="debug">ZIP: ${content.length} chars | QueerList: ${content.contains("QueerList") ? "YES" : "NO"}</div><hr>');
        
  //       // Simple body extraction (no complex regex)
  //       String mainContent = content;
  //       int bodyStart = content.indexOf('<body');
  //       if (bodyStart != -1) {
  //         int bodyEnd = content.indexOf('</body>', bodyStart);
  //         if (bodyEnd != -1) {
  //           mainContent = content.substring(bodyStart + 6, bodyEnd);
  //         }
  //       }
        
  //       // Remove scripts/styles safely
  //       mainContent = mainContent
  //         .replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', multiLine: true), '')
  //         .replaceAll(RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', multiLine: true), '');
        
  //       html.writeln(mainContent);
  //       html.writeln('</div>');
  //     }
      
  //     html.writeln('</body></html>');
  //     print('✅ ZIP HTML: ${html.length} chars');
  //     return html.toString();
      
  //   } catch (e) {
  //     print('❌ ERROR: $e');
  //     return '<h1 style="color:red;text-align:center;padding:50px;">Error loading book</h1>';
  //   }
  // }

    // 🔥 MAIN LOADING FUNCTION
    Future<String?> _loadBookContent(String epubPath) async {
      try {
        print('📖 Loading EPUB: $epubPath');
        final bytes = await File(epubPath).readAsBytes();
        final epub = await EpubReader.readBook(bytes);
        
        print('✅ Title: ${epub.Title}');
        print('✅ epubx Chapters: ${epub.Chapters?.length ?? 0}');
        
        // FORCE ZIP - epubx HtmlContent is USELESS (XML headers only)
        print('🔄 epubx too small → ZIP FORCED');
        return await _zipDeepScan(epubPath, bytes, epub);
        
      } catch (e) {
        print('❌ ERROR: $e');
        return '<h1 style="color:red;text-align:center;padding:50px;">Error: $e</h1>';
      }
    }

    // 🔥 ZIP CONTENT SCANNER
    Future<String?> _zipDeepScan(String epubPath, List<int> bytes, EpubBook epub) async {
      final archive = ZipDecoder().decodeBytes(bytes);
      print('📦 ZIP: ${archive.length} files');
      
      List<MapEntry<String, ArchiveFile>> contentFiles = [];
      
      // Scan ALL HTML/XHTML files >500 chars
      for (final file in archive) {
        if (file.isFile) {
          final nameLower = file.name.toLowerCase();
          if ((nameLower.endsWith('.html') || nameLower.endsWith('.xhtml')) && 
              file.content.length > 500) {
            final preview = utf8.decode(file.content).substring(0, 200);
            print('📄 ${file.name.padRight(50)} | ${file.content.length} chars');
            print('   Preview: "$preview"');
            contentFiles.add(MapEntry(file.name, file));
          }
        }
      }
      
      print('✅ Found ${contentFiles.length} content files');
      
      if (contentFiles.isEmpty) {
        return '<h1 style="color:orange;text-align:center;">No content files >500 chars found</h1>';
      }
      
      // Build COMPLETE HTML
      StringBuffer html = StringBuffer();
      html.writeln('<!DOCTYPE html><html><head><meta charset="UTF-8">');
      html.writeln('<style>');
      html.writeln('body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;background:#fdfdfd;color:#333;}');
      html.writeln('h1{text-align:center;color:#2c5aa0;margin-bottom:40px;}');
      html.writeln('h2{color:#2c5aa0;border-bottom:2px solid #eee;padding:20px 0 10px;margin-top:40px;}');
      html.writeln('.debug{background:#e3f2fd;padding:15px;border-left:5px solid #2196f3;margin:20px 0;font-family:monospace;font-size:14px;border-radius:5px;box-shadow:0 2px 5px rgba(0,0,0,0.1);}');
      html.writeln('.chapter{margin-bottom:60px;padding-bottom:40px;border-bottom:2px solid #eee;}');
      html.writeln('p{margin:15px 0;line-height:1.8;}');
      html.writeln('</style></head><body>');
      html.writeln('<h1>📖 ${epub.Title ?? "Book"}</h1>');
      
      for (final entry in contentFiles) {
        final file = entry.value;
        final fileName = entry.key;
        try {
          String content = utf8.decode(file.content);
          
          html.writeln('<div class="chapter">');
          html.writeln('<h2>📄 ${fileName.split('/').last}</h2>');
          
          // DEBUG BOX
          html.writeln('<div class="debug">');
          html.writeln('📏 <strong>File:</strong> $fileName');
          html.writeln('📏 <strong>Size:</strong> ${content.length} chars');
          html.writeln('🔍 <strong>Preview:</strong> ${content.length > 100 ? content.substring(0, 100) + "..." : content}');
          html.writeln('✅ <strong>QueerList:</strong> ${content.contains("QueerList") ? "YES ✓" : "NO"}');
          html.writeln('</div><hr>');
          
          // CLEAN CONTENT
          String cleanContent = _stripXmlHeaders(content);
          cleanContent = _removeStylesScripts(cleanContent);
          
          html.writeln(cleanContent);
          html.writeln('</div>');
          
        } catch (e) {
          print('⚠️ Error processing ${file.name}: $e');
          html.writeln('<div class="chapter"><h2>⚠️ Error: ${file.name}</h2><p style="color:red;">$e</p></div>');
        }
      }
      
      html.writeln('</body></html>');
      print('✅ Generated HTML: ${html.length} chars');
      return html.toString();
    }

    // 🔥 XML HEADER STRIPPER
    String _stripXmlHeaders(String html) {
      // Remove XML declaration + DOCTYPE
      html = html.replaceAll(RegExp(r'<\?xml[^>]*\?>', multiLine: true), '');
      html = html.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', multiLine: true), '');
      
      // Extract body content safely
      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', multiLine: true, caseSensitive: false).firstMatch(html);
      if (bodyMatch != null && bodyMatch.group(1) != null) {
        html = bodyMatch.group(1)!;
      }
      
      return html.trim();
    }

    // 🔥 STYLE/SCRIPT REMOVER
    String _removeStylesScripts(String html) {
      html = html.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', multiLine: true, caseSensitive: false), '');
      html = html.replaceAll(RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', multiLine: true, caseSensitive: false), '');
      return html;
    }


  // Future<String?> _loadBookContent(String epubPath) async {
  //   try {
  //     print('📖 Loading EPUB: $epubPath');
  //     final bytes = await File(epubPath).readAsBytes();
  //     final epub = await EpubReader.readBook(bytes);
      
  //     print('✅ Title: ${epub.Title}');
  //     print('✅ epubx Chapters: ${epub.Chapters?.length ?? 0}');
      
  //     // DEBUG: Show ALL chapters + decide path
  //     List<EpubChapter> realChapters = [];
  //     for (int i = 0; i < (epub.Chapters?.length ?? 0); i++) {
  //       final chapter = epub.Chapters![i];
  //       final content = chapter.HtmlContent ?? '';
  //       final preview = content.length > 100 ? content.substring(0, 100) : content;
        
  //       print('📄 Chapter ${i+1}: "${chapter.Title}" (${content.length} chars)');
  //       print('   Preview: "$preview"');
        
  //       // NULL-SAFE story detection
  //       final titleLower = (chapter.Title ?? '').toLowerCase();
  //       final hasRealContent = content.length > 1000 &&
  //           !titleLower.contains('contents') &&
  //           !titleLower.contains('cover') &&
  //           (content.contains('QueerList') || 
  //           content.contains('<p>') || 
  //           titleLower.contains('part'));
        
  //       if (hasRealContent) {
  //         realChapters.add(chapter);
  //         print('   ✅ STORY CHAPTER DETECTED!');
  //       }
  //     }
      
  //     // Use epubx ONLY if we found real story chapters
  //     if (realChapters.isNotEmpty) {
  //       print('🎉 Using epubx (${realChapters.length} story chapters)');
  //       return _buildEpubxHtml(realChapters);
  //     }
      
  //     print('🔄 No story chapters → ZIP fallback');
  //     return await _zipFallback(epubPath, bytes);
  //   } catch (e) {
  //     print('❌ ERROR: $e');
  //     return '<h1 style="color:red;">Error: $e</h1>';
  //   }
  // }

  String _buildEpubxHtml(List<EpubChapter> chapters) {
    StringBuffer html = StringBuffer();
    html.writeln('<!DOCTYPE html><html><head><meta charset="UTF-8">');
    html.writeln('<style>body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;background:white;color:#333;}.chapter{margin-bottom:60px;padding-bottom:40px;border-bottom:2px solid #eee;}h2{text-align:center;color:#2c5aa0;}.debug{background:#f0f8ff;padding:15px;border-left:4px solid #007acc;margin:20px 0;}</style></head><body>');
    
    html.writeln('<h1 style="text-align:center;">📖 Book Chapters</h1>');
    
    for (final chapter in chapters) {
      final content = chapter.HtmlContent ?? '';
      html.writeln('<div class="chapter">');
      html.writeln('<h2>${chapter.Title}</h2><hr>');
      
      // Debug box ON EVERY CHAPTER
      html.writeln('<div class="debug">');
      html.writeln('Chars: ${content.length} | Preview: "${content.length > 50 ? content.substring(0, 50) : content}"');
      html.writeln('QueerList: ${content.contains("QueerList") ? "✅ YES" : "❌ NO"}');
      html.writeln('</div>');
      
      html.writeln(content);
      html.writeln('</div>');
    }
    
    html.writeln('</body></html>');
    return html.toString();
  }

  Future<String?> _zipFallback(String epubPath, List<int> bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      print('📦 ZIP: ${archive.length} files');
      
      List<ArchiveFile> contentFiles = [];
      for (final file in archive) {
        if (file.isFile) {
          final nameLower = file.name.toLowerCase();
          if ((nameLower.endsWith('.html') || nameLower.endsWith('.xhtml')) && 
              file.content.length > 500) {
            final preview = utf8.decode(file.content).substring(0, 100);
            print('📄 ZIP: ${file.name} (${file.content.length} chars) | "$preview"');
            contentFiles.add(file);
          }
        }
      }
      
      if (contentFiles.isEmpty) {
        print('❌ No ZIP content found');
        return '<h1>No content files >500 chars</h1>';
      }
      
      print('✅ Building ZIP HTML (${contentFiles.length} files)');
      StringBuffer html = StringBuffer('<!DOCTYPE html><html><head><meta charset="UTF-8"><style>body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;}</style></head><body>');
      
      for (final file in contentFiles.take(5)) {
        final content = utf8.decode(file.content);
        html.writeln('<h2 style="color:#2c5aa0;">${file.name.split('/').last}</h2><hr>');
        html.writeln('<div style="background:#f9f9f9;padding:15px;">${content.length} chars | QueerList: ${content.contains("QueerList") ? "✅ YES" : "NO"}</div>');
        html.writeln(content.substring(0, 8000)); // First 8k chars
        html.writeln('<hr style="margin:60px 0;">');
      }
      
      html.writeln('</body></html>');
      return html.toString();
    } catch (e) {
      print('❌ ZIP ERROR: $e');
      return '<h1>ZIP Error: $e</h1>';
    }
  }

  // String _buildEpubxHtml(EpubBook epub) {
  //   StringBuffer html = StringBuffer();
  //   html.writeln('<!DOCTYPE html><html><head><meta charset="UTF-8">');
  //   html.writeln('<style>body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;}');
  //   html.writeln('.chapter{margin-bottom:60px;padding-bottom:40px;border-bottom:2px solid #eee;}h2{color:#2c5aa0;}</style></head><body>');
    
  //   html.writeln('<h1>📖 ${epub.Title ?? "Book"}</h1>');
    
  //   for (int i = 0; i < (epub.Chapters?.length ?? 0); i++) {
  //     final chapter = epub.Chapters![i];
  //     final content = chapter.HtmlContent ?? '<p>No content</p>';
  //     html.writeln('<div class="chapter"><h2>${chapter.Title ?? "Chapter $i"}</h2><hr>$content</div>');
  //   }
    
  //   html.writeln('</body></html>');
  //   return html.toString();
  // }

  Future<String?> _extractZipContent({required Archive archive}) async {
    try {
      print('🔍 Scanning ${archive.files.length} ZIP files...');
      
      // Find HTML files with real content
      final htmlFiles = <ArchiveFile>[];
      for (final file in archive) {
        if (file.isFile && file.name.toLowerCase().endsWith('.html')) {
          final content = utf8.decode(file.content);
          if (content.length > 2000) {  // Real chapter content
            htmlFiles.add(file);
            print('✅ ZIP HTML: ${file.name} (${content.length} chars)');
            print('Preview: ${content.substring(0, 200)}...');
          }
        }
      }
      
      if (htmlFiles.isEmpty) {
        print('❌ No real HTML files found in ZIP');
        return null;
      }
      
      // Build HTML from ZIP files
      StringBuffer html = StringBuffer();
      html.writeln('<!DOCTYPE html><html><head><meta charset="UTF-8"><title>ZIP Content</title>');
      html.writeln('<style>body{font-family:Georgia,serif;font-size:18px;line-height:1.7;max-width:900px;margin:20px auto;padding:20px;}h2{color:#2c5aa0;border-bottom:2px solid #eee;}</style></head><body>');
      
      for (final file in htmlFiles.take(3)) {
        final content = utf8.decode(file.content);
        final bodyMatch = RegExp(r'<body[^>]*>([\\s\\S]*?)</body>', dotAll: true).firstMatch(content);
        final bodyContent = bodyMatch?.group(1) ?? content;
        
        html.writeln('<h2>📄 ${file.name.split('/').last}</h2><hr>');
        html.writeln('<div class="debug">ZIP: ${content.length} chars | QueerList: ${content.contains("QueerList") ? "✅ YES" : "NO"}</div>');
        html.writeln(bodyContent.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ''));
        html.writeln('<hr style="margin: 60px 0;">');
      }
      
      html.writeln('</body></html>');
      return html.toString();
    } catch (e) {
      print('❌ ZIP extraction failed: $e');
      return null;
    }
  }

  String _cleanChapterHtml(String html) {
    String cleaned = html;
    
    // 1. Remove external CSS links
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'<link[^>]+?>', caseSensitive: false), 
      (match) => ''
    );
    
    // 2. Remove external JS  
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), 
      (match) => ''
    );

    // 4. Fix HTML tags
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'<html[^>]*>', caseSensitive: false), 
      (match) => '<div'
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'</html>', caseSensitive: false), 
      (match) => '</div>'
    );
    
    // 5. STRIP ALL HTML TAGS (fallback - gets plain text)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'<[^>]+?>'), 
      (match) => ''
    );
    
    return cleaned.trim().isNotEmpty ? cleaned : '<p>(Content not readable)</p>';
  }

  String _fixEpubHtml(String rawHtml, String bookTitle) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        * { box-sizing: border-box; }
        body { 
          font-family: Georgia, serif; 
          font-size: 18px; line-height: 1.7; 
          margin: 0; padding: 20px;
          background: white; color: #333;
          overflow-y: auto !important; height: 100vh;
        }
        .book { max-width: 900px; margin: 0 auto; }
        .chapter { 
          margin-bottom: 60px; padding-bottom: 40px;
          border-bottom: 2px solid #eee; min-height: 800px;
          page-break-after: always;
        }
        h1, h2 { text-align: center; color: #2c5aa0; }
        img { max-width: 100%; height: auto; }
        ::selection { background: #ffeb3b !important; }
      </style>
    </head>
    <body>
      <div class="book">
        <h1 style="margin-bottom: 40px;">📖 $bookTitle</h1>
        ${rawHtml}
      </div>
      <!-- JS DISABLED - fixes List<dynamic> crash -->
    </body>
    </html>
    ''';
  }

  String _wrapChapterHtml(String chapterHtml, String bookTitle) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        body { 
          font-family: Georgia, serif; 
          font-size: 18px; 
          line-height: 1.6; 
          margin: 20px; 
          padding: 20px;
          max-width: 800px;
          margin: auto;
          background: white;
          color: black;
        }
        ::selection { background: yellow; }
      </style>
    </head>
    <body>
      <h1 style="text-align: center;">📖 $bookTitle</h1>
      <hr>
      ${chapterHtml}
      <script>
        document.addEventListener('selectionchange', () => {
          const sel = window.getSelection();
          if (sel.toString().trim() && window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onTextSelected', {
              cfi: 'ch1:' + Math.random(),
              text: sel.toString().trim()
            });
          }
        });
      </script>
    </body>
    </html>
    ''';
  }

  String _getFallbackContent() {
    return '''
    <h1>📖 ${widget.book.title}</h1>
    <p>Chapter 1 content would load here...</p>
    <div style="height: 3000px; padding: 40px;">
      <h2>Demo Content</h2>
      <p>EPUB parsing failed. Select this text to test highlights.</p>
    </div>
    ''';
  }




  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    // Handle text selection
    controller.addJavaScriptHandler(
      handlerName: 'onTextSelected',
      callback: (args) {
        final data = args[0] as Map<String, dynamic>;
        final readerState = context.read<ReaderState>();
        readerState.setSelection(data['cfi'], data['text']);
        _showSelectionMenu(data);
      },
    );

    // Handle location change
    controller.addJavaScriptHandler(
      handlerName: 'onLocationChanged',
      callback: (args) {
        final data = args[0] as Map<String, dynamic>;
        final readerState = context.read<ReaderState>();
        readerState.updatePosition(
          data['cfi'],
          data['progress'].toDouble(),
          data['currentPage'],
          data['totalPages'],
        );
      },
    );

    // Handle highlight tap
    controller.addJavaScriptHandler(
      handlerName: 'onHighlightTapped',
      callback: (args) {
        final cfi = args[0] as String;
        final readerState = context.read<ReaderState>();
        final highlight = readerState.getHighlightByCfi(cfi);
        if (highlight != null) {
          _showHighlightOptions(highlight);
        }
      },
    );

    // Handle search results
    controller.addJavaScriptHandler(
      handlerName: 'onSearchResults',
      callback: (args) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(args[0]);
        });
      },
    );
  }

  Future<void> _injectReaderScript() async {
    // This is a simplified EPUB.js-like reader script
    // In production, you'd want to use epub.js or a similar library
    const readerScript = '''
      (function() {
        // EPUB Reader JavaScript
        // This would contain the full EPUB rendering logic
        // For now, we'll set up the basic handlers
        
        document.addEventListener('selectionchange', function() {
          const selection = window.getSelection();
          if (selection && selection.toString().trim()) {
            // Get CFI for selection (simplified)
            const range = selection.getRangeAt(0);
            const cfi = generateCFI(range);
            window.flutter_inappwebview.callHandler('onTextSelected', {
              cfi: cfi,
              text: selection.toString(),
              rect: range.getBoundingClientRect()
            });
          }
        });
        
        function generateCFI(range) {
          // Simplified CFI generation - in production use epub.js
          return 'epubcfi(/6/4[chapter]!/4/2/1:' + range.startOffset + ')';
        }
        
        window.applyHighlight = function(cfi, color) {
          // Apply highlight to text at CFI location
          console.log('Applying highlight:', cfi, color);
        };
        
        window.removeHighlight = function(cfi) {
          console.log('Removing highlight:', cfi);
        };
        
        window.navigateTo = function(cfi) {
          console.log('Navigating to:', cfi);
        };
        
        window.setTheme = function(settings) {
          document.body.style.backgroundColor = settings.backgroundColor;
          document.body.style.color = settings.textColor;
          document.body.style.fontFamily = settings.fontFamily;
          document.body.style.fontSize = settings.fontSize + 'px';
          document.body.style.lineHeight = settings.lineHeight;
          document.body.style.textAlign = settings.textAlign;
        };
        
        window.search = function(query) {
          // Implement search logic
          const results = [];
          // ... search through content
          window.flutter_inappwebview.callHandler('onSearchResults', results);
        };
      })();
    ''';
    
    await _webViewController?.evaluateJavascript(source: readerScript);
  }

  Future<void> _applySettings(ReadingSettings settings) async {
    final settingsJson = jsonEncode({
      'backgroundColor': '#${settings.theme.backgroundColor.value.toRadixString(16).substring(2)}',
      'textColor': '#${settings.theme.textColor.value.toRadixString(16).substring(2)}',
      'fontFamily': settings.fontFamily,
      'fontSize': settings.fontSize,
      'lineHeight': settings.lineHeight,
      'textAlign': settings.textAlign.name,
    });
    
    await _webViewController?.evaluateJavascript(
      source: 'window.setTheme($settingsJson);',
    );
  }

  Future<void> _loadHighlights(List<Highlight> highlights) async {
    for (final highlight in highlights) {
      await _webViewController?.evaluateJavascript(
        source: "window.applyHighlight('${highlight.cfi}', '${highlight.color.cssColor}');",
      );
    }
  }

  void _navigateToCfi(String cfi) {
    _webViewController?.evaluateJavascript(
      source: "window.navigateTo('$cfi');",
    );
  }

  void _navigateToChapter(String href) {
    _webViewController?.loadFile(assetFilePath: 'file://$_extractedPath/$href');
  }

  void _navigateToHighlight(Highlight highlight) {
    Navigator.pop(context); // Close drawer
    _navigateToCfi(highlight.cfi);
  }

  void _navigateToBookmark(String cfi) {
    Navigator.pop(context); // Close drawer
    _navigateToCfi(cfi);
  }

  void _showSelectionMenu(Map<String, dynamic> data) {
    final rect = data['rect'] as Map<String, dynamic>;
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        rect['left'],
        rect['top'] - 50,
        rect['right'],
        rect['bottom'],
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.highlight, size: 20),
              SizedBox(width: 8),
              Text('Highlight'),
            ],
          ),
          onTap: () => _showHighlightColorPicker(data['cfi'], data['text']),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.comment, size: 20),
              SizedBox(width: 8),
              Text('Comment'),
            ],
          ),
          onTap: () => _addHighlightWithComment(data['cfi'], data['text']),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: data['text']));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.share, size: 20),
              SizedBox(width: 8),
              Text('Share'),
            ],
          ),
          onTap: () {
            // Implement share functionality
          },
        ),
      ],
    );
  }

  void _showHighlightColorPicker(String cfi, String text) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose highlight color',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: HighlightColor.values.map((color) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addHighlight(cfi, text, color);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addHighlight(String cfi, String text, HighlightColor color) async {
    final readerState = context.read<ReaderState>();
    final highlight = await readerState.addHighlight(
      cfi: cfi,
      text: text,
      color: color,
    );
    
    await _webViewController?.evaluateJavascript(
      source: "window.applyHighlight('${highlight.cfi}', '${highlight.color.cssColor}');",
    );
    
    readerState.clearSelection();
  }

  Future<void> _addHighlightWithComment(String cfi, String text) async {
    // First add the highlight
    final readerState = context.read<ReaderState>();
    final highlight = await readerState.addHighlight(
      cfi: cfi,
      text: text,
      color: HighlightColor.yellow,
    );
    
    await _webViewController?.evaluateJavascript(
      source: "window.applyHighlight('${highlight.cfi}', '${highlight.color.cssColor}');",
    );
    
    readerState.clearSelection();
    
    // Then show comment sheet
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => CommentSheet(highlight: highlight),
      );
    }
  }

  void _showHighlightOptions(Highlight highlight) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.comment),
              title: const Text('View/Add Comments'),
              trailing: highlight.commentCount > 0
                  ? CircleAvatar(
                      radius: 12,
                      child: Text('${highlight.commentCount}'),
                    )
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CommentSheet(highlight: highlight),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Add/Edit Note'),
              onTap: () {
                Navigator.pop(ctx);
                _showNoteEditor(highlight);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Change Color'),
              onTap: () {
                Navigator.pop(ctx);
                _showHighlightColorPicker(highlight.cfi, highlight.text);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Highlight', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final readerState = context.read<ReaderState>();
                await readerState.deleteHighlight(highlight.id);
                await _webViewController?.evaluateJavascript(
                  source: "window.removeHighlight('${highlight.cfi}');",
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteEditor(Highlight highlight) {
    final controller = TextEditingController(text: highlight.note);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write your note...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final readerState = context.read<ReaderState>();
              readerState.updateHighlight(
                highlight.copyWith(note: controller.text),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ReaderState readerState) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState!.openDrawer(),
            ),
            Expanded(
              child: Text(
                widget.book.title,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                readerState.isCurrentPageBookmarked()
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: Colors.white,
              ),
              onPressed: _toggleBookmark,
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: const Icon(Icons.text_format, color: Colors.white),
              onPressed: _showSettingsSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderState readerState) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress slider
              SliderTheme(
                data: SliderThemeData(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  trackHeight: 2,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withOpacity(0.3),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: readerState.progress,
                  onChanged: (value) {
                    // Navigate to percentage
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${readerState.currentPage} of ${readerState.totalPages}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    '${(readerState.progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  if (readerState.estimatedReadingTimeLeft != null)
                    Text(
                      '${readerState.estimatedReadingTimeLeft} min left',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isSearching = false;
                          _searchResults = [];
                          _searchController.clear();
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search in book...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (query) {
                          _webViewController?.evaluateJavascript(
                            source: "window.search('$query');",
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_searchResults.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (ctx, index) {
                      final result = _searchResults[index];
                      return ListTile(
                        title: Text(
                          result['excerpt'] ?? '',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          result['chapter'] ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        onTap: () {
                          setState(() => _isSearching = false);
                          _navigateToCfi(result['cfi']);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleBookmark() async {
    final readerState = context.read<ReaderState>();
    
    if (readerState.isCurrentPageBookmarked()) {
      final bookmark = readerState.bookmarks.firstWhere(
        (b) => b.cfi == readerState.currentCfi,
      );
      await readerState.deleteBookmark(bookmark.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark removed')),  // ← Fix this
        );
      }
    } else {
      await readerState.addBookmark();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark added')),   // ← And this
        );
      }
    }
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ThemeSettingsSheet(
        onSettingsChanged: (settings) async {
          final readerState = context.read<ReaderState>();
          await readerState.updateSettings(settings);
          await _applySettings(settings);
        },
      ),
    );
  }
}