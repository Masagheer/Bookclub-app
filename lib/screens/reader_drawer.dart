// lib/widgets/reader/reader_drawer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/highlight.dart';
import '../../models/bookmark.dart';
import '../../models/chapter.dart';
import '../../providers/reader_state.dart';

class ReaderDrawer extends StatefulWidget {
  final Function(String href) onChapterSelected;
  final Function(Highlight highlight) onHighlightSelected;
  final Function(String cfi) onBookmarkSelected;

  const ReaderDrawer({
    super.key,
    required this.onChapterSelected,
    required this.onHighlightSelected,
    required this.onBookmarkSelected,
  });

  @override
  State<ReaderDrawer> createState() => _ReaderDrawerState();
}

class _ReaderDrawerState extends State<ReaderDrawer> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Consumer<ReaderState>(
        builder: (context, readerState, child) {
          return Column(
            children: [
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  bottom: 8,
                ),
                child: Text(
                  readerState.currentBook?.title ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TabBar(
                controller: _tabController,
                labelStyle: const TextStyle(fontSize: 12),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.list, size: 20),
                    text: 'Contents',
                  ),
                  Tab(
                    icon: Stack(
                      children: [
                        const Icon(Icons.bookmark, size: 20),
                        if (readerState.bookmarks.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: CircleAvatar(
                              radius: 6,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(
                                '${readerState.bookmarks.length}',
                                style: const TextStyle(fontSize: 8, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    text: 'Bookmarks',
                  ),
                  Tab(
                    icon: Stack(
                      children: [
                        const Icon(Icons.highlight, size: 20),
                        if (readerState.highlights.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: CircleAvatar(
                              radius: 6,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Text(
                                '${readerState.highlights.length}',
                                style: const TextStyle(fontSize: 8, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    text: 'Highlights',
                  ),
                  const Tab(
                    icon: Icon(Icons.note, size: 20),
                    text: 'Notes',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChaptersList(readerState.chapters),
                    _buildBookmarksList(readerState.bookmarks),
                    _buildHighlightsList(readerState.highlights),
                    _buildNotesList(readerState.highlights.where((h) => h.note != null && h.note!.isNotEmpty).toList()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChaptersList(List<Chapter> chapters) {
    if (chapters.isEmpty) {
      return const Center(child: Text('No chapters found'));
    }

    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return _buildChapterTile(chapter, 0);
      },
    );
  }

  Widget _buildChapterTile(Chapter chapter, int depth) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16 + (depth * 16).toDouble(), right: 16),
          title: Text(
            chapter.title,
            style: TextStyle(
              fontSize: depth == 0 ? 14 : 13,
              fontWeight: depth == 0 ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          onTap: () => widget.onChapterSelected(chapter.href),
        ),
        ...chapter.subChapters.map((sub) => _buildChapterTile(sub, depth + 1)),
      ],
    );
  }

  Widget _buildBookmarksList(List<Bookmark> bookmarks) {
    if (bookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('No bookmarks yet', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        return ListTile(
          leading: const Icon(Icons.bookmark),
          title: Text(bookmark.title ?? 'Bookmark ${index + 1}'),
          subtitle: bookmark.excerpt != null
              ? Text(
                  bookmark.excerpt!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () => widget.onBookmarkSelected(bookmark.cfi),
        );
      },
    );
  }

  Widget _buildHighlightsList(List<Highlight> highlights) {
    if (highlights.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.highlight, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('No highlights yet', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: highlights.length,
      itemBuilder: (context, index) {
        final highlight = highlights[index];
        return ListTile(
          leading: Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: highlight.color.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          title: Text(
            highlight.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: highlight.commentCount > 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.comment, size: 16),
                    const SizedBox(width: 4),
                    Text('${highlight.commentCount}'),
                  ],
                )
              : null,
          onTap: () => widget.onHighlightSelected(highlight),
        );
      },
    );
  }

  Widget _buildNotesList(List<Highlight> highlightsWithNotes) {
    if (highlightsWithNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('No notes yet', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: highlightsWithNotes.length,
      itemBuilder: (context, index) {
        final highlight = highlightsWithNotes[index];
        return ListTile(
          title: Text(
            highlight.note!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '"${highlight.text}"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          onTap: () => widget.onHighlightSelected(highlight),
        );
      },
    );
  }
}