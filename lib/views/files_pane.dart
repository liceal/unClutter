import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;
import '../services/app_state.dart';
import '../theme/app_theme.dart';

enum _ViewMode { list, grid, details }

class FilesPane extends StatefulWidget {
  final AppState state;
  final bool isDark;

  const FilesPane({super.key, required this.state, required this.isDark});

  @override
  State<FilesPane> createState() => _FilesPaneState();
}

class _FilesPaneState extends State<FilesPane> {
  bool _isDragging = false;
  String _searchQuery = '';
  _ViewMode _viewMode = _ViewMode.list;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static const _imageExts = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'ico',
    'svg',
  ];

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _imageExts.contains(ext);
  }

  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    File file,
    VoidCallback onDelete,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'open',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 14),
              SizedBox(width: 8),
              Text('打开文件', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'show_in_explorer',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 14),
              SizedBox(width: 8),
              Text('在资源管理器中显示', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy_file',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 14),
              SizedBox(width: 8),
              Text('复制文件路径', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy_path',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.insert_link_rounded, size: 14),
              SizedBox(width: 8),
              Text('打开文件所在目录', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: isDark ? Colors.red[300] : Colors.red[700],
              ),
              const SizedBox(width: 8),
              Text(
                '删除文件',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.red[300] : Colors.red[700],
                ),
              ),
            ],
          ),
        ),
      ],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? const Color(0xFF262626) : Colors.white,
    );

    if (result == null) return;

    switch (result) {
      case 'open':
        widget.state.openFile(file);
        break;
      case 'show_in_explorer':
        if (Platform.isWindows) {
          Process.run('explorer.exe', ['/select,', file.path]);
        } else if (Platform.isMacOS) {
          Process.run('open', ['-R', file.path]);
        }
        break;
      case 'copy_file':
        Clipboard.setData(ClipboardData(text: file.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('文件路径已复制到剪贴板', style: TextStyle(fontSize: 11)),
              duration: Duration(seconds: 1),
            ),
          );
        }
        break;
      case 'copy_path':
        if (Platform.isWindows) {
          Process.run('explorer.exe', ['/select,', file.path]);
        } else if (Platform.isMacOS) {
          Process.run('open', ['-R', file.path]);
        }
        break;
      case 'delete':
        onDelete();
        break;
    }
  }

  /// 返回 (图标, 颜色)
  (IconData, Color) _getFileIconAndColor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      // 压缩包
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
        return (Icons.inventory_2_rounded, const Color(0xFFFF9800));
      // PDF
      case 'pdf':
        return (Icons.picture_as_pdf_rounded, const Color(0xFFE53935));
      // Word
      case 'doc':
      case 'docx':
      case 'odt':
        return (Icons.article_rounded, const Color(0xFF1565C0));
      // Excel
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (Icons.table_chart_rounded, const Color(0xFF2E7D32));
      // PPT
      case 'ppt':
      case 'pptx':
        return (Icons.slideshow_rounded, const Color(0xFFD84315));
      // 文本 / 代码
      case 'txt':
        return (Icons.text_snippet_rounded, const Color(0xFF546E7A));
      case 'md':
        return (Icons.description_rounded, const Color(0xFF455A64));
      case 'json':
        return (Icons.data_object_rounded, const Color(0xFF6D4C41));
      case 'xml':
      case 'html':
        return (Icons.code_rounded, const Color(0xFFE65100));
      case 'yaml':
      case 'yml':
      case 'ini':
      case 'conf':
        return (Icons.settings_applications_rounded, const Color(0xFF5C6BC0));
      case 'dart':
      case 'flutter':
        return (Icons.flutter_dash_rounded, const Color(0xFF0288D1));
      case 'js':
      case 'ts':
      case 'vue':
      case 'py':
      case 'java':
      case 'kt':
      case 'swift':
      case 'sh':
      case 'bat':
      case 'cmd':
        return (Icons.terminal_rounded, const Color(0xFF388E3C));
      case 'css':
        return (Icons.css_rounded, const Color(0xFF1976D2));
      // 图片
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'ico':
      case 'svg':
        return (Icons.image_rounded, const Color(0xFF7B1FA2));
      // 音频
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'm4a':
      case 'aac':
        return (Icons.audio_file_rounded, const Color(0xFFF50057));
      // 视频
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
        return (Icons.video_file_rounded, const Color(0xFF6A1B9A));
      // 可执行
      case 'exe':
      case 'msi':
        return (Icons.memory_rounded, const Color(0xFF37474F));
      default:
        return (Icons.insert_drive_file_rounded, const Color(0xFF78909C));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.getAccentColor(
      widget.state.settings.themeColorName,
      widget.isDark,
    );

    final files = widget.state.storedFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final fileName = file.uri.pathSegments.last.toLowerCase();
      return fileName.contains(_searchQuery.toLowerCase());
    }).toList();

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (detail) async {
        setState(() => _isDragging = false);
        await widget.state.addDroppedFiles(
          detail.files.map((f) => f.path).toList(),
        );
      },
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Search + View Toggle ──
                Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent &&
                        pointerSignal.scrollDelta.dy < 0) {
                      widget.state.collapsePanel();
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchBar(
                          controller: _searchController,
                          isDark: widget.isDark,
                          showFolderBtn: _searchController.text.isEmpty,
                          onOpenFolder: () =>
                              widget.state.openFilesDirectoryInExplorer(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (_viewMode == _ViewMode.list) {
                              _viewMode = _ViewMode.grid;
                            } else if (_viewMode == _ViewMode.grid) {
                              _viewMode = _ViewMode.details;
                            } else {
                              _viewMode = _ViewMode.list;
                            }
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _viewMode == _ViewMode.list
                                  ? Icons.grid_view_rounded
                                  : Icons.view_list_rounded,
                              size: 15,
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // ── File Content ──
                Expanded(
                  child: files.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.move_to_inbox_outlined,
                                size: 32,
                                color: widget.isDark
                                    ? Colors.white24
                                    : Colors.black26,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? '未找到匹配文件'
                                    : '拖拽文件到此处暂存',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDark
                                      ? Colors.white30
                                      : Colors.black.withOpacity(0.3),
                                ),
                              ),
                            ],
                          ),
                        )
                      : _viewMode == _ViewMode.list
                      ? _buildListView(files)
                      : _viewMode == _ViewMode.grid
                      ? _buildGridView(files)
                      : _buildDetailsView(files),
                ),
              ],
            ),
          ),

          // ── Drag overlay ──
          if (_isDragging)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: (widget.isDark ? Colors.black : Colors.white)
                      .withOpacity(0.88),
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                ),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: accentColor, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 32,
                          color: accentColor,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '释放文件以暂存',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListView(List<File> files) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: files.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, index) {
        final file = files[index];
        final fileName = file.uri.pathSegments.last;
        final (icon, iconColor) = _getFileIconAndColor(file.path);
        return _ListFileCard(
          file: file,
          fileName: fileName,
          icon: icon,
          iconColor: iconColor,
          isImage: _isImage(file.path),
          isDark: widget.isDark,
          onOpen: () => widget.state.openFile(file),
          onDelete: () => widget.state.deleteFile(file),
          onContextMenu: (ctx, pos) => _showContextMenu(
            ctx,
            pos,
            file,
            () => widget.state.deleteFile(file),
          ),
        );
      },
    );
  }

  Widget _buildGridView(List<File> files) {
    return GridView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (ctx, index) {
        final file = files[index];
        final fileName = file.uri.pathSegments.last;
        final (icon, iconColor) = _getFileIconAndColor(file.path);
        return _GridFileCard(
          file: file,
          fileName: fileName,
          icon: icon,
          iconColor: iconColor,
          isImage: _isImage(file.path),
          isDark: widget.isDark,
          onOpen: () => widget.state.openFile(file),
          onDelete: () => widget.state.deleteFile(file),
          onContextMenu: (ctx, pos) => _showContextMenu(
            ctx,
            pos,
            file,
            () => widget.state.deleteFile(file),
          ),
        );
      },
    );
  }

  Widget _buildDetailsView(List<File> files) {
    return Column(
      children: [
        // Table Headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '名称',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const SizedBox(
                width: 50,
                child: Text(
                  '大小',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 65,
                child: Text(
                  '创建时间',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Colors.grey),
        const SizedBox(height: 2),
        // List items
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: files.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (ctx, index) {
              final file = files[index];
              final fileName = file.uri.pathSegments.last;
              final (icon, iconColor) = _getFileIconAndColor(file.path);
              final stat = file.existsSync() ? file.statSync() : null;
              final sizeStr = stat != null ? formatFileSize(stat.size) : '—';

              String dateStr = '—';
              if (stat != null) {
                final date = Platform.isWindows ? stat.changed : stat.modified;
                dateStr =
                    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              }

              return _DetailsFileCard(
                file: file,
                fileName: fileName,
                sizeStr: sizeStr,
                dateStr: dateStr,
                icon: icon,
                iconColor: iconColor,
                isImage: _isImage(file.path),
                isDark: widget.isDark,
                onOpen: () => widget.state.openFile(file),
                onDelete: () => widget.state.deleteFile(file),
                onContextMenu: (ctx, pos) => _showContextMenu(
                  ctx,
                  pos,
                  file,
                  () => widget.state.deleteFile(file),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ══════════════════════════════════════════════════
// Search Bar widget
// ══════════════════════════════════════════════════
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final bool showFolderBtn;
  final VoidCallback onOpenFolder;

  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.showFolderBtn,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: '搜索暂存文件...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 6),
            child: Icon(
              Icons.search_rounded,
              size: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 14,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => controller.clear(),
                      child: const Icon(Icons.clear, size: 12),
                    ),
                  ),
                )
              : showFolderBtn
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onOpenFolder,
                      child: const Icon(Icons.folder_open_outlined, size: 14),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 20,
            minHeight: 12,
          ),
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// List Card
// ══════════════════════════════════════════════════
class _ListFileCard extends StatefulWidget {
  final File file;
  final String fileName;
  final IconData icon;
  final Color iconColor;
  final bool isImage;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(BuildContext, Offset) onContextMenu;

  const _ListFileCard({
    required this.file,
    required this.fileName,
    required this.icon,
    required this.iconColor,
    required this.isImage,
    required this.isDark,
    required this.onOpen,
    required this.onDelete,
    required this.onContextMenu,
  });

  @override
  State<_ListFileCard> createState() => _ListFileCardState();
}

class _ListFileCardState extends State<_ListFileCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem();
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = true);
          });
        },
        onExit: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = false);
          });
        },
        child: GestureDetector(
          onDoubleTap: widget.onOpen,
          onSecondaryTapUp: (details) =>
              widget.onContextMenu(context, details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // File icon / thumbnail
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: widget.isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.file(
                            widget.file,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              widget.icon,
                              size: 13,
                              color: widget.iconColor,
                            ),
                          ),
                        )
                      : Icon(widget.icon, size: 13, color: widget.iconColor),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                // Delete button
                if (_isHovered)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDelete,
                      onDoubleTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 10,
                          color: widget.isDark
                              ? Colors.red[300]
                              : Colors.red[700],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Grid Card
// ══════════════════════════════════════════════════
class _GridFileCard extends StatefulWidget {
  final File file;
  final String fileName;
  final IconData icon;
  final Color iconColor;
  final bool isImage;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(BuildContext, Offset) onContextMenu;

  const _GridFileCard({
    required this.file,
    required this.fileName,
    required this.icon,
    required this.iconColor,
    required this.isImage,
    required this.isDark,
    required this.onOpen,
    required this.onDelete,
    required this.onContextMenu,
  });

  @override
  State<_GridFileCard> createState() => _GridFileCardState();
}

class _GridFileCardState extends State<_GridFileCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem();
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = true);
          });
        },
        onExit: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = false);
          });
        },
        child: GestureDetector(
          onDoubleTap: widget.onOpen,
          onSecondaryTapUp: (details) =>
              widget.onContextMenu(context, details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.black.withOpacity(0.05))
                  : (widget.isDark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.02)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered
                    ? (widget.isDark ? Colors.white12 : Colors.black12)
                    : Colors.transparent,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: widget.isImage
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    widget.file,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => Icon(
                                      widget.icon,
                                      size: 30,
                                      color: widget.iconColor,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: widget.iconColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    widget.icon,
                                    size: 22,
                                    color: widget.iconColor,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: widget.isDark
                              ? Colors.white70
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete button on hover
                if (_isHovered)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onDelete,
                        onDoubleTap: () {},
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black54
                                : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 10,
                            color: widget.isDark
                                ? Colors.red[300]
                                : Colors.red[700],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// File Preview Dialog
// ══════════════════════════════════════════════════
class _FilePreviewDialog extends StatefulWidget {
  final File file;
  final String fileName;
  final bool isImage;
  final bool isText;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _FilePreviewDialog({
    required this.file,
    required this.fileName,
    required this.isImage,
    required this.isText,
    required this.isDark,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  String? _textContent;
  bool _loadingText = false;

  @override
  void initState() {
    super.initState();
    if (widget.isText) {
      _loadingText = true;
      widget.file
          .readAsString()
          .then((content) {
            if (mounted) {
              setState(() {
                _textContent = content.length > 4000
                    ? '${content.substring(0, 4000)}\n...(仅预览前 4000 字符)'
                    : content;
                _loadingText = false;
              });
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _loadingText = false);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;

    // File metadata
    final stat = widget.file.existsSync() ? widget.file.statSync() : null;
    final size = stat != null ? _FilesPaneState.formatFileSize(stat.size) : '—';
    final creationTime = stat != null
        ? (Platform.isWindows ? stat.changed : stat.modified)
        : null;
    final createdStr = creationTime != null
        ? '${creationTime.year}-${creationTime.month.toString().padLeft(2, '0')}-${creationTime.day.toString().padLeft(2, '0')}'
        : '—';

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(size, style: TextStyle(fontSize: 11, color: subColor)),
                  const SizedBox(width: 8),
                  Text(
                    createdStr,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(Icons.close, size: 16, color: subColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: widget.isDark ? Colors.white12 : Colors.black12,
            ),

            // ── Preview area ──
            Flexible(child: _buildPreviewBody(textColor, subColor)),

            Divider(
              height: 1,
              color: widget.isDark ? Colors.white12 : Colors.black12,
            ),

            // ── Actions ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '删除',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.isDark
                                ? Colors.red[300]
                                : Colors.red[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onOpen,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '用应用打开',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody(Color textColor, Color subColor) {
    if (widget.isImage) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            widget.file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: subColor),
                  const SizedBox(height: 8),
                  Text(
                    '无法加载图片',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.isText) {
      if (_loadingText) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_textContent != null) {
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Text(
              _textContent!,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        );
      }
    }

    // Generic file info
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 52, color: subColor),
          const SizedBox(height: 12),
          Text('此文件类型不支持预览', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 4),
          Text(
            '点击「用应用打开」在外部程序中查看',
            style: TextStyle(fontSize: 11, color: subColor),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Details Card
// ══════════════════════════════════════════════════
class _DetailsFileCard extends StatefulWidget {
  final File file;
  final String fileName;
  final String sizeStr;
  final String dateStr;
  final IconData icon;
  final Color iconColor;
  final bool isImage;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(BuildContext, Offset) onContextMenu;

  const _DetailsFileCard({
    required this.file,
    required this.fileName,
    required this.sizeStr,
    required this.dateStr,
    required this.icon,
    required this.iconColor,
    required this.isImage,
    required this.isDark,
    required this.onOpen,
    required this.onDelete,
    required this.onContextMenu,
  });

  @override
  State<_DetailsFileCard> createState() => _DetailsFileCardState();
}

class _DetailsFileCardState extends State<_DetailsFileCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem();
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = true);
          });
        },
        onExit: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = false);
          });
        },
        child: GestureDetector(
          onDoubleTap: widget.onOpen,
          onSecondaryTapUp: (details) =>
              widget.onContextMenu(context, details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: widget.isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            widget.file,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              widget.icon,
                              size: 11,
                              color: widget.iconColor,
                            ),
                          ),
                        )
                      : Icon(widget.icon, size: 11, color: widget.iconColor),
                ),
                const SizedBox(width: 6),
                // Name
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Size
                SizedBox(
                  width: 50,
                  child: Text(
                    widget.sizeStr,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date
                SizedBox(
                  width: 65,
                  child: Text(
                    widget.dateStr,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Delete Button Space or Close Icon
                SizedBox(
                  width: 16,
                  height: 16,
                  child: _isHovered
                      ? MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onDelete,
                            onDoubleTap: () {},
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 10,
                                color: widget.isDark
                                    ? Colors.red[300]
                                    : Colors.red[700],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
