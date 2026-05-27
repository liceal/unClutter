import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/app_state.dart';

class NotesPane extends StatefulWidget {
  final AppState state;
  final bool isDark;

  const NotesPane({super.key, required this.state, required this.isDark});

  @override
  State<NotesPane> createState() => _NotesPaneState();
}

class _NotesPaneState extends State<NotesPane> {
  late TextEditingController _editorController;
  final ScrollController _scrollController = ScrollController();
  String _activeNoteId = '';
  bool _showList = true;

  @override
  void initState() {
    super.initState();
    _editorController = TextEditingController();
    _syncActiveNote();
  }

  @override
  void didUpdateWidget(NotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActiveNote();
  }

  @override
  void dispose() {
    _editorController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncActiveNote() {
    final active = widget.state.activeNote;
    if (active != null) {
      if (_activeNoteId != active.id) {
        _activeNoteId = active.id;
        _editorController.text = active.content;
      }
    } else {
      _editorController.clear();
      _activeNoteId = '';
    }
  }

  void _onContentChanged(String val) {
    widget.state.updateActiveNoteContent(val);
  }

  void _showDeleteConfirmDialog(BuildContext context, Note note, {bool fromDetail = false}) async {
    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除便签？'),
        content: const Text('您确定要删除该便签吗？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('删除'),
            onPressed: () async {
              final nav = Navigator.of(ctx);
              nav.pop();
              await widget.state.deleteNote(note);
              _syncActiveNote();
              if (fromDetail) {
                setState(() => _showList = true);
              } else {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
    widget.state.setDialogOpen(false);
  }

  String _getSnippet(String content) {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '无内容';
    return lines.first;
  }

  Widget _buildList(List<Note> allNotes) {
    return ListView.builder(
      itemCount: allNotes.length,
      itemBuilder: (context, index) {
        final note = allNotes[index];
        final snippet = _getSnippet(note.content);
        final dateStr = '${note.updatedAt.month}-${note.updatedAt.day} ${note.updatedAt.hour.toString().padLeft(2, '0')}:${note.updatedAt.minute.toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                widget.state.selectNote(note);
                _syncActiveNote();
                setState(() => _showList = false);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      onPressed: () => _showDeleteConfirmDialog(context, note, fromDetail: false),
                      color: widget.isDark ? Colors.white54 : Colors.black45,
                      hoverColor: Colors.red.withValues(alpha: 0.1),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      tooltip: '删除便签',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail(Note active) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
      child: TextField(
        controller: _editorController,
        scrollController: _scrollController,
        maxLines: null,
        minLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 13, height: 1.4),
        decoration: InputDecoration(
          hintText: '开始书写便签内容...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: widget.isDark ? Colors.white24 : Colors.black26,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onChanged: _onContentChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state.activeNote;
    final allNotes = widget.state.notes;

    if (active == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with buttons
          SizedBox(
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_showList) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 14),
                    tooltip: '删除当前便签',
                    onPressed: () => _showDeleteConfirmDialog(context, active, fromDetail: true),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Icon(Icons.add, size: 16),
                  tooltip: '新建便签',
                  onPressed: () async {
                    await widget.state.createNote();
                    _syncActiveNote();
                    setState(() => _showList = false);
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.menu, size: 16),
                  tooltip: _showList ? '当前为列表视图' : '返回列表视图',
                  onPressed: () {
                    setState(() => _showList = !_showList);
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Main Content Area with Transition
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<bool>(_showList),
                child: _showList ? _buildList(allNotes) : _buildDetail(active),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
