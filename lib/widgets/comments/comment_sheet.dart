// lib/widgets/comments/comment_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/highlight.dart';
import '../../models/comment.dart';
import '../../providers/reader_state.dart';

class CommentSheet extends StatefulWidget {
  final Highlight highlight;

  const CommentSheet({super.key, required this.highlight});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _controller = TextEditingController();
  List<Comment> _comments = [];
  bool _isLoading = true;
  String? _replyingTo;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    final readerState = context.read<ReaderState>();
    _comments = await readerState.getCommentsForHighlight(widget.highlight.id);
    setState(() => _isLoading = false);
  }

  Future<void> _submitComment() async {
    if (_controller.text.trim().isEmpty) return;

    final readerState = context.read<ReaderState>();
    await readerState.addComment(
      highlightId: widget.highlight.id,
      body: _controller.text.trim(),
      parentId: _replyingTo,
    );

    _controller.clear();
    _replyingTo = null;
    await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Highlighted text
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.highlight.color.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.highlight.color.color),
                ),
                child: Text(
                  '"${widget.highlight.text}"',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const Divider(height: 24),

              // Comments list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'No comments yet',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start the discussion!',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) {
                              return _buildCommentTile(_comments[index], 0);
                            },
                          ),
              ),

              // Reply indicator
              if (_replyingTo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Replying to comment')),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _replyingTo = null),
                      ),
                    ],
                  ),
                ),

              // Input
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          maxLines: null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _submitComment,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentTile(Comment comment, int depth) {
    final readerState = context.read<ReaderState>();
    final isOwner = comment.userId == readerState.currentUserId;

    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  comment.userName.isNotEmpty ? comment.userName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.userName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(comment.createdAt),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(comment.body),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _replyingTo = comment.id),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                          ),
                          child: const Text('Reply'),
                        ),
                        if (isOwner)
                          TextButton(
                            onPressed: () {
                              // Delete comment
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Replies
          ...comment.replies.map((reply) => _buildCommentTile(reply, depth + 1)),
          if (depth == 0) const Divider(),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}