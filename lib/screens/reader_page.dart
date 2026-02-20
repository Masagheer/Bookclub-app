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

  Future<String?> _loadBookContent(String epubPath) async {
    try {
      print('📖 Loading EPUB: $epubPath');
      final bytes = await File(epubPath).readAsBytes();
      final epub = await EpubReader.readBook(bytes);
      
      print('✅ Title: ${epub.Title}');
      print('✅ Total Chapters: ${epub.Chapters?.length ?? 0}');
      
      StringBuffer fullBook = StringBuffer();
      fullBook.writeln('<!DOCTYPE html><html><head>');
      fullBook.writeln('<meta charset="UTF-8">');
      fullBook.writeln('<style>');
      fullBook.writeln('* { box-sizing: border-box; }');
      fullBook.writeln('body { font-family: Georgia, serif; font-size: 18px; line-height: 1.7; margin: 0; padding: 20px; background: white; color: #333; }');
      fullBook.writeln('.book { max-width: 900px; margin: 0 auto; }');
      fullBook.writeln('.chapter { margin-bottom: 60px; padding-bottom: 40px; border-bottom: 2px solid #eee; page-break-after: always; }');
      fullBook.writeln('h1, h2 { text-align: center; color: #2c5aa0; }');
      fullBook.writeln('.debug { background: #f0f8ff; padding: 15px; border-left: 4px solid #007acc; margin: 20px 0; }');
      fullBook.writeln('</style></head><body>');
      fullBook.writeln('<div class="book">');
      fullBook.writeln('<h1>📖 ${epub.Title}</h1>');
      
      if (epub.Chapters == null || epub.Chapters!.isEmpty) {
        fullBook.writeln('<h2>No chapters found</h2>');
      } else {
        for (int i = 0; i < epub.Chapters!.length; i++) {
          final chapter = epub.Chapters![i];
          final rawContent = chapter.HtmlContent ?? '';
          
          print('Chapter ${i+1}: "${chapter.Title}" (${rawContent.length} chars)');
          
          fullBook.writeln('<div class="chapter" id="chapter_$i">');
          fullBook.writeln('<h2>${chapter.Title ?? "Chapter ${i+1}"}</h2>');
          fullBook.writeln('<hr style="margin: 30px 0;">');
          
          // DEBUG: Show RAW content + analysis
          fullBook.writeln('<div class="debug">');
          fullBook.writeln('<strong>DEBUG INFO:</strong><br>');
          fullBook.writeln('Chars: ${rawContent.length}<br>');
          fullBook.writeln('Starts with: "${rawContent.length > 100 ? rawContent.substring(0, 100) : rawContent}"<br>');
          fullBook.writeln('Contains body text: ${rawContent.contains("<body") ? "YES" : "NO"}<br>');
          fullBook.writeln('Contains QueerList: ${rawContent.contains("QueerList") ? "YES" : "NO"}');
          fullBook.writeln('</div>');
          
          // ALWAYS show RAW HTML (no cleaning)
          if (rawContent.isNotEmpty) {
            fullBook.writeln(rawContent);
          } else {
            fullBook.writeln('<p style="color: #888;">EMPTY chapter content</p>');
          }
          
          fullBook.writeln('</div>');
        }
      }
      
      fullBook.writeln('</div></body></html>');
      
      final htmlContent = fullBook.toString();
      print('✅ Generated HTML: ${htmlContent.length} chars');
      print('✅ First 500 chars: ${htmlContent.substring(0, htmlContent.length > 500 ? 500 : htmlContent.length)}');
      
      return htmlContent;
    } catch (e) {
      print('❌ EPUB ERROR: $e');
      return '<h1 style="color: red; text-align: center;">Error loading book: $e</h1>';
    }
  }

  // Future<String?> _loadBookContent(String epubPath) async {
  //   try {
  //     print('📖 Loading EPUB: $epubPath');
  //     final bytes = await File(epubPath).readAsBytes();
  //     final epub = await EpubReader.readBook(bytes);
      
  //     print('✅ Title: ${epub.Title}');
      
  //     StringBuffer fullBook = StringBuffer();
  //     fullBook.writeln('<div class="book">');
      
  //     // PRIORITY 1: Try chapters with REAL content
  //     if (epub.Chapters != null) {
  //       for (int i = 0; i < epub.Chapters!.length; i++) {
  //         final chapter = epub.Chapters![i];
  //         final content = chapter.HtmlContent ?? '';
          
  //         print('Chapter ${i+1}: ${chapter.Title} (${content.length} chars)');
          
  //         fullBook.writeln('<div class="chapter" id="chapter_$i">');
  //         fullBook.writeln('<h2>${chapter.Title ?? "Chapter ${i+1}"}</h2>');
  //         fullBook.writeln('<hr>');
          
  //         // Show content if it has real text (not just metadata)
  //         if (content.length > 1000) {  // REAL CONTENT
  //           fullBook.writeln(content);
  //         } else {
  //           fullBook.writeln('<p style="color: #888;">(Short metadata only - ${content.length} chars)</p>');
  //         }
  //         fullBook.writeln('</div>');
  //       }
  //     }
      
  //     fullBook.writeln('</div>');
      
  //     print('✅ WebView loaded content: ${fullBook.length} chars');
  //     return fullBook.toString();
  //   } catch (e) {
  //     print('❌ Error: $e');
  //     return '<h1>Error loading book</h1>';
  //   }
  // }

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