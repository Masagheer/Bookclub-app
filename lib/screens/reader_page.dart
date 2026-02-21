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
import 'package:archive/archive.dart';
// IMPORTANT: Import flutter_html with prefix to avoid Style conflict
import 'package:flutter_html/flutter_html.dart' as html;

/// Helper class to represent a block of text
class TextBlock {
  final String html;
  final String plainText;
  final String tag;

  TextBlock({
    required this.html,
    required this.plainText,
    required this.tag,
  });
}

class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  // Data
  List<String> chapterHtmls = [];
  List<String> paginatedPages = [];

  // State flags
  bool isLoadingChapters = true;
  bool isPaginating = false;

  // Raw content before pagination
  List<String> rawChapterContents = [];

  // User-controllable settings
  double _fontSize = 18.0;
  double _lineHeight = 1.6;
  double _headingFontSize = 22.0;

  // Page dimensions (calculated after first build)
  Size? _pageSize;

  // Controllers
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // WebView (if needed)
  InAppWebViewController? _webViewController;
  String? _extractedPath;
  bool _isReady = false;
  bool _showControls = true;

  final EpubService _epubService = EpubService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  int _currentSearchIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================================
  // LOAD CHAPTERS
  // ============================================================================
  Future<void> _loadChapters() async {
    try {
      setState(() => isLoadingChapters = true);

      final bytes = await File(widget.book.filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      List<String> allChapters = [];

      for (final file in archive) {
        if (file.isFile) {
          final nameLower = file.name.toLowerCase();
          if ((nameLower.endsWith('.html') || nameLower.endsWith('.xhtml')) &&
              file.content.length > 500) {
            String content = utf8.decode(file.content);
            content = _stripXmlHeaders(content);
            content = _extractBodyContent(content);
            allChapters.add(content);
          }
        }
      }

      setState(() {
        rawChapterContents = allChapters;
        chapterHtmls = allChapters.take(50).toList();
        isLoadingChapters = false;
      });

      print('✅ Loaded ${rawChapterContents.length} raw chapters');
    } catch (e) {
      print('❌ Chapter load error: $e');
      setState(() => isLoadingChapters = false);
    }
  }

  // ============================================================================
  // PAGINATION
  // ============================================================================
  Future<void> _paginateContent(Size size) async {
    if (rawChapterContents.isEmpty || isPaginating) return;

    if (_pageSize != null &&
        (_pageSize!.width - size.width).abs() < 5 &&
        (_pageSize!.height - size.height).abs() < 5 &&
        paginatedPages.isNotEmpty) {
      return;
    }

    setState(() => isPaginating = true);
    _pageSize = size;

    List<String> allPages = [];
    double availableWidth = size.width - 32;
    double availableHeight = size.height - 100;

    for (String chapterHtml in rawChapterContents) {
      List<TextBlock> blocks = _parseHtmlToBlocks(chapterHtml);
      List<String> chapterPages =
          await _paginateBlocks(blocks, Size(availableWidth, availableHeight));
      allPages.addAll(chapterPages);
    }

    setState(() {
      paginatedPages = allPages;
      isPaginating = false;
    });

    print('✅ Created ${paginatedPages.length} paginated pages');
  }

  List<TextBlock> _parseHtmlToBlocks(String html) {
    List<TextBlock> blocks = [];
    final blockRegex = RegExp(
      r'<(p|h[1-6]|div|blockquote|li)[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in blockRegex.allMatches(html)) {
      String tag = match.group(1)!.toLowerCase();
      String content = match.group(2)!;
      String plainText = content.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      if (plainText.isNotEmpty) {
        blocks.add(TextBlock(
          html: '<$tag>$content</$tag>',
          plainText: plainText,
          tag: tag,
        ));
      }
    }

    if (blocks.isEmpty && html.trim().isNotEmpty) {
      String plainText = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (plainText.isNotEmpty) {
        blocks.add(TextBlock(
          html: '<p>$html</p>',
          plainText: plainText,
          tag: 'p',
        ));
      }
    }

    return blocks;
  }

  double _measureBlockHeight(TextBlock block, double availableWidth) {
    final textStyle = _getTextStyleForTag(block.tag);
    final textPainter = TextPainter(
      text: TextSpan(text: block.plainText, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    textPainter.layout(maxWidth: availableWidth);
    double margins = _getMarginsForTag(block.tag);
    return textPainter.height + margins;
  }

  TextStyle _getTextStyleForTag(String tag) {
    if (tag.startsWith('h')) {
      return TextStyle(
        fontSize: _headingFontSize,
        fontWeight: FontWeight.bold,
        height: _lineHeight,
      );
    }
    return TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
    );
  }

  double _getMarginsForTag(String tag) {
    if (tag.startsWith('h')) {
      return 32.0;
    }
    return 24.0;
  }

  Future<List<String>> _paginateBlocks(
      List<TextBlock> blocks, Size pageSize) async {
    List<String> pages = [];
    StringBuffer currentPageHtml = StringBuffer();
    double currentPageHeight = 0;

    for (var block in blocks) {
      double blockHeight = _measureBlockHeight(block, pageSize.width);

      if (currentPageHeight + blockHeight <= pageSize.height) {
        currentPageHtml.writeln(block.html);
        currentPageHeight += blockHeight;
      } else {
        if (currentPageHtml.isNotEmpty) {
          pages.add(currentPageHtml.toString());
          currentPageHtml.clear();
          currentPageHeight = 0;
        }

        if (blockHeight > pageSize.height) {
          currentPageHtml.writeln(block.html);
          currentPageHeight = blockHeight;
        } else {
          currentPageHtml.writeln(block.html);
          currentPageHeight = blockHeight;
        }
      }
    }

    if (currentPageHtml.isNotEmpty) {
      pages.add(currentPageHtml.toString());
    }

    return pages;
  }

  List<String> _splitIntoSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  // ============================================================================
  // FONT SIZE & SETTINGS
  // ============================================================================
  void _changeFontSize(int delta, BuildContext context) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(12, 32);
    });
    if (_pageSize != null) {
      _paginateContent(_pageSize!);
    }
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ThemeSettingsSheet(
        onSettingsChanged: (settings) async {
          final readerState =
              Provider.of<ReaderState>(context, listen: false);
          await readerState.updateSettings(settings);
        },
      ),
    );
  }

  // ============================================================================
  // BOOKMARK
  // ============================================================================
  void _toggleBookmark(BuildContext context) async {
    final readerState = Provider.of<ReaderState>(context, listen: false);
    if (readerState.isCurrentPageBookmarked()) {
      final bookmark = readerState.bookmarks.firstWhere(
        (b) => b.cfi == readerState.currentCfi,
      );
      await readerState.deleteBookmark(bookmark.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark removed')),
        );
      }
    } else {
      await readerState.addBookmark();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark added')),
        );
      }
    }
  }

  // ============================================================================
  // HIGHLIGHTS
  // ============================================================================
  void _showHighlightColorPicker(
      String cfi, String text, BuildContext context) {
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
                      _addHighlight(cfi, text, color, context);
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

  Future<void> _addHighlight(
      String cfi, String text, HighlightColor color, BuildContext context) async {
    final readerState = Provider.of<ReaderState>(context, listen: false);
    final highlight = await readerState.addHighlight(
      cfi: cfi,
      text: text,
      color: color,
    );
    await _webViewController?.evaluateJavascript(
      source:
          "window.applyHighlight('${highlight.cfi}', '${highlight.color.cssColor}');",
    );
    readerState.clearSelection();
  }

  Future<void> _addHighlightWithComment(
      String cfi, String text, BuildContext context) async {
    final readerState = Provider.of<ReaderState>(context, listen: false);
    final highlight = await readerState.addHighlight(
      cfi: cfi,
      text: text,
      color: HighlightColor.yellow,
    );
    await _webViewController?.evaluateJavascript(
      source:
          "window.applyHighlight('${highlight.cfi}', '${highlight.color.cssColor}');",
    );
    readerState.clearSelection();

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => CommentSheet(highlight: highlight),
      );
    }
  }

  void _showHighlightOptions(Highlight highlight, BuildContext context) {
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
                _showNoteEditor(highlight, context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Change Color'),
              onTap: () {
                Navigator.pop(ctx);
                _showHighlightColorPicker(highlight.cfi, highlight.text, context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Highlight',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final readerState =
                    Provider.of<ReaderState>(context, listen: false);
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

  void _showNoteEditor(Highlight highlight, BuildContext context) {
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
              final readerState =
                  Provider.of<ReaderState>(context, listen: false);
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

  // ============================================================================
  // NAVIGATION
  // ============================================================================
  void _navigateToCfi(String cfi) {
    _webViewController?.evaluateJavascript(
      source: "window.navigateTo('$cfi');",
    );
  }

  void _navigateToChapter(String href) {
    _webViewController?.loadFile(
        assetFilePath: 'file://$_extractedPath/$href');
  }

  void _navigateToHighlight(Highlight highlight, BuildContext context) {
    Navigator.pop(context);
    _navigateToCfi(highlight.cfi);
  }

  void _navigateToBookmark(String cfi, BuildContext context) {
    Navigator.pop(context);
    _navigateToCfi(cfi);
  }

  // ============================================================================
  // SELECTION MENU
  // ============================================================================
  void _showSelectionMenu(
      Map<String, dynamic> data, BuildContext context) {
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
          onTap: () =>
              _showHighlightColorPicker(data['cfi'], data['text'], context),
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.comment, size: 20),
              SizedBox(width: 8),
              Text('Comment'),
            ],
          ),
          onTap: () =>
              _addHighlightWithComment(data['cfi'], data['text'], context),
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
      ],
    );
  }

  // ============================================================================
  // JAVASCRIPT HANDLERS
  // ============================================================================
  void _setupJavaScriptHandlers(
      InAppWebViewController controller, BuildContext context) {
    controller.addJavaScriptHandler(
      handlerName: 'onTextSelected',
      callback: (args) {
        final data = args[0] as Map<String, dynamic>;
        final readerState =
            Provider.of<ReaderState>(context, listen: false);
        readerState.setSelection(data['cfi'], data['text']);
        _showSelectionMenu(data, context);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onLocationChanged',
      callback: (args) {
        final data = args[0] as Map<String, dynamic>;
        final readerState =
            Provider.of<ReaderState>(context, listen: false);
        readerState.updatePosition(
          data['cfi'],
          data['progress'].toDouble(),
          data['currentPage'],
          data['totalPages'],
        );
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onHighlightTapped',
      callback: (args) {
        final cfi = args[0] as String;
        final readerState =
            Provider.of<ReaderState>(context, listen: false);
        final highlight = readerState.getHighlightByCfi(cfi);
        if (highlight != null) {
          _showHighlightOptions(highlight, context);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onSearchResults',
      callback: (args) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(args[0]);
        });
      },
    );
  }

  // ============================================================================
  // SEARCH OVERLAY
  // ============================================================================
  Widget _buildSearchOverlay(BuildContext context) {
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
                        decoration: const InputDecoration(
                          hintText: 'Search in book...',
                          hintStyle: TextStyle(color: Colors.white54),
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
                          style: const TextStyle(color: Colors.white54),
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

  // ============================================================================
  // UTILS
  // ============================================================================
  String _stripXmlHeaders(String content) {
    content = content.replaceAll(RegExp(r'<\?xml[^>]*\?>'), '');
    content = content.replaceAll(RegExp(r'<!DOCTYPE[^>]*>'), '');
    return content;
  }

  String _extractBodyContent(String html) {
    html = html.replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            caseSensitive: false, dotAll: true),
        '');
    html = html.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>',
            caseSensitive: false, dotAll: true),
        '');
    final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    return bodyMatch?.group(1) ?? html;
  }

  String _removeStylesScripts(String html) {
    html = html.replaceAll(
        RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>',
            multiLine: true, caseSensitive: false),
        '');
    html = html.replaceAll(
        RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>',
            multiLine: true, caseSensitive: false),
        '');
    return html;
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderState>(
      builder: (context, readerState, child) {
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(widget.book.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.text_decrease),
                onPressed: () => _changeFontSize(-2, context),
              ),
              IconButton(
                icon: const Icon(Icons.text_increase),
                onPressed: () => _changeFontSize(2, context),
              ),
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ],
          ),
          drawer: ReaderDrawer(
            onChapterSelected: (href) {
              _navigateToChapter(href);
              Navigator.pop(context);
            },
            onHighlightSelected: (highlight) {
              _navigateToHighlight(highlight, context);
            },
            onBookmarkSelected: (cfi) {
              _navigateToBookmark(cfi, context);
            },
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final screenSize =
                  Size(constraints.maxWidth, constraints.maxHeight);

              // Trigger Pagination if needed
              if (!isLoadingChapters &&
                  !isPaginating &&
                  paginatedPages.isEmpty &&
                  rawChapterContents.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _paginateContent(screenSize);
                });
              }

              // Loading States
              if (isLoadingChapters || isPaginating) {
                return const Center(child: CircularProgressIndicator());
              }

              if (paginatedPages.isEmpty) {
                return const Center(child: Text('No content available'));
              }

              // THE READER (Horizontal PageView)
              return Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.horizontal,
                    itemCount: paginatedPages.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      return Container(
                        width: screenSize.width,
                        height: screenSize.height,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        child: html.Html(
                          data: paginatedPages[index],
                          style: {
                            'body': html.Style(
                              fontSize: html.FontSize(_fontSize),
                              lineHeight:
                                  html.LineHeight.number(_lineHeight),
                              margin: html.Margins.zero,
                              padding: html.HtmlPaddings.zero,
                            ),
                            'p': html.Style(
                                margin: html.Margins.only(bottom: 12)),
                            'h1': html.Style(
                                fontSize:
                                    html.FontSize(_headingFontSize + 4)),
                            'h2': html.Style(
                                fontSize:
                                    html.FontSize(_headingFontSize + 2)),
                          },
                        ),
                      );
                    },
                  ),

                  // Page Indicator
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentPage + 1} / ${paginatedPages.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  // Search Overlay
                  if (_isSearching) _buildSearchOverlay(context),
                ],
              );
            },
          ),
        );
      },
    );
  }
}