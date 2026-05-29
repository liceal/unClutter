import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;
import '../services/app_state.dart';
import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import 'components/animated_press.dart';

enum _ViewMode { grid, details }

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
  _ViewMode _viewMode = _ViewMode.grid;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _detailsScrollController = ScrollController();
  bool _isDragDropReady = false;
  bool _showSizeSlider = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (mounted) {
        setState(() {
          _isDragDropReady = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    _detailsScrollController.dispose();
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
    if (FileSystemEntity.isDirectorySync(path)) return false;
    final ext = path.split('.').last.toLowerCase();
    return _imageExts.contains(ext);
  }

  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    FileSystemEntity file,
    VoidCallback onDelete,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDir = file is Directory;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    widget.state.setDialogOpen(true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'open',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, size: 14),
              const SizedBox(width: 8),
              Text(isDir ? '打开文件夹' : '打开文件', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'show_in_explorer',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 14),
              const SizedBox(width: 8),
              Text(Platform.isMacOS ? '在 Finder 中显示' : '在资源管理器中显示', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy_path',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 14),
              const SizedBox(width: 8),
              Text(isDir ? '复制文件夹路径' : '复制文件路径', style: const TextStyle(fontSize: 11)),
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
                isDir ? '删除文件夹' : '删除文件',
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
    widget.state.setDialogOpen(false);

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
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: file.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isDir ? '文件夹路径已复制到剪贴板' : '文件路径已复制到剪贴板', style: const TextStyle(fontSize: 11)),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        break;
      case 'delete':
        onDelete();
        break;
    }
  }

  /// 返回 (图标, 颜色)
  (IconData, Color) _getFileIconAndColor(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      return (Icons.folder_rounded, const Color(0xFFFFB300));
    }
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
      final segments = file.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final fileName = segments.isEmpty ? '' : segments.last.toLowerCase();
      return fileName.contains(_searchQuery.toLowerCase());
    }).toList();

    if (!_isDragDropReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '正在加载暂存区...',
              style: TextStyle(
                fontSize: 11,
                color: widget.isDark
                    ? Colors.white30
                    : Colors.black.withOpacity(0.3),
              ),
            ),
          ],
        ),
      );
    }

    final isCompact = widget.state.settings.themeStyle == ThemeStyle.compact;
    final mainContent = Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isCompact ? 2 : 4),
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
                          themeStyle: widget.state.settings.themeStyle,
                        ),
                      ),
                      SizedBox(width: isCompact ? 2 : 4),
                      if (_showSizeSlider) ...[
                        SizedBox(
                          width: 80,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              activeTrackColor: widget.isDark ? Colors.white60 : Colors.black54,
                              inactiveTrackColor: widget.isDark ? Colors.white12 : Colors.black12,
                              thumbColor: widget.isDark ? Colors.white : Colors.black87,
                            ),
                            child: Slider(
                              value: widget.state.fileDisplaySize,
                              min: 60.0,
                              max: 160.0,
                              onChanged: (val) {
                                widget.state.updateFileDisplaySize(val);
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: isCompact ? 2 : 4),
                      ],
                      Tooltip(
                        message: '调整显示大小',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedPress(
                            onTap: () => setState(() => _showSizeSlider = !_showSizeSlider),
                            child: Container(
                              width: isCompact ? 26 : 32,
                              height: isCompact ? 26 : 32,
                              decoration: BoxDecoration(
                                color: _showSizeSlider
                                    ? (widget.isDark
                                        ? Colors.white.withOpacity(0.12)
                                        : Colors.black.withOpacity(0.08))
                                    : (widget.isDark
                                        ? Colors.white.withOpacity(0.06)
                                        : Colors.black.withOpacity(0.04)),
                                borderRadius: BorderRadius.circular(isCompact ? 0 : 8),
                              ),
                              child: Icon(
                                Icons.photo_size_select_large_rounded,
                                size: 15,
                                color: widget.isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isCompact ? 2 : 4),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedPress(
                          onTap: () => setState(() {
                            if (_viewMode == _ViewMode.grid) {
                              _viewMode = _ViewMode.details;
                            } else {
                              _viewMode = _ViewMode.grid;
                            }
                          }),
                          child: Container(
                            width: isCompact ? 26 : 32,
                            height: isCompact ? 26 : 32,
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(isCompact ? 0 : 8),
                            ),
                            child: Icon(
                              _viewMode == _ViewMode.grid
                                  ? Icons.view_list_rounded
                                  : Icons.grid_view_rounded,
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
                SizedBox(height: isCompact ? 2 : 4),

                // ── File Content ──
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapUp: (details) =>
                        _showEmptySpaceContextMenu(context, details.globalPosition),
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
                        : _viewMode == _ViewMode.grid
                        ? _buildGridView(files)
                        : _buildDetailsView(files),
                  ),
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
      );

    return _isDragDropReady
        ? sdd.DropRegion(
            formats: const [sdd.Formats.fileUri],
            onDropEnter: (event) {
              final isInternal = event.session.items.any((item) => item.localData == 'internal_file_drag');
              if (!isInternal) {
                setState(() => _isDragging = true);
              }
            },
            onDropLeave: (event) => setState(() => _isDragging = false),
            onDropOver: (event) {
              final isInternal = event.session.items.any((item) => item.localData == 'internal_file_drag');
              return isInternal ? sdd.DropOperation.none : sdd.DropOperation.copy;
            },
            onPerformDrop: (event) async {
              final isInternal = event.session.items.any((item) => item.localData == 'internal_file_drag');
              if (isInternal) return;
              setState(() => _isDragging = false);
              final filePaths = <String>[];
              final items = event.session.items;
              int completed = 0;
              if (items.isEmpty) return;

              for (final item in items) {
                final reader = item.dataReader;
                if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
                  reader.getValue<Uri>(sdd.Formats.fileUri, (uri) {
                    if (uri != null) {
                      filePaths.add(uri.toFilePath());
                    }
                    completed++;
                    if (completed == items.length && filePaths.isNotEmpty) {
                      widget.state.addDroppedFiles(filePaths);
                    }
                  }, onError: (err) {
                    completed++;
                    if (completed == items.length && filePaths.isNotEmpty) {
                      widget.state.addDroppedFiles(filePaths);
                    }
                  });
                } else {
                  completed++;
                  if (completed == items.length && filePaths.isNotEmpty) {
                    widget.state.addDroppedFiles(filePaths);
                  }
                }
              }
            },
            child: mainContent,
          )
        : mainContent;
  }

  void _showNewNameDialog(BuildContext context, bool isFolder) async {
    final textController = TextEditingController(text: isFolder ? '新建文件夹' : '新建文件.txt');
    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: Text(isFolder ? '新建文件夹' : '新建文件'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFolder ? '请输入文件夹名称' : '请输入文件名称',
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('创建'),
            onPressed: () async {
              final name = textController.text;
              Navigator.of(ctx).pop();
              if (isFolder) {
                await widget.state.createNewDirectory(name);
              } else {
                await widget.state.createNewFile(name);
              }
              setState(() {});
            },
          ),
        ],
      ),
    );
    widget.state.setDialogOpen(false);
  }

  void _showEmptySpaceContextMenu(BuildContext context, Offset globalPosition) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    widget.state.setDialogOpen(true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'new_file',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.note_add_rounded, size: 14),
              SizedBox(width: 8),
              Text('新建文件', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'new_folder',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.create_new_folder_rounded, size: 14),
              SizedBox(width: 8),
              Text('新建文件夹', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'open_folder',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 14),
              SizedBox(width: 8),
              Text('打开暂存目录', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? const Color(0xFF262626) : Colors.white,
    );
    widget.state.setDialogOpen(false);

    if (result == null) return;

    switch (result) {
      case 'new_file':
        if (context.mounted) _showNewNameDialog(context, false);
        break;
      case 'new_folder':
        if (context.mounted) _showNewNameDialog(context, true);
        break;
      case 'open_folder':
        widget.state.openFilesDirectoryInExplorer();
        break;
    }
  }



  Widget _buildGridView(List<FileSystemEntity> files) {
    return GridView.builder(
      key: const PageStorageKey('files_grid_view'),
      controller: _gridScrollController,
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: widget.state.fileDisplaySize,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (ctx, index) {
        final file = files[index];
        final segments = file.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final fileName = segments.isEmpty ? '未知' : segments.last;
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

  Widget _buildDetailsView(List<FileSystemEntity> files) {
    final scaleFactor = (widget.state.fileDisplaySize / 110.0).clamp(0.8, 1.4);
    return Column(
      children: [
        // Table Headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '名称',
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 50 * scaleFactor,
                child: Text(
                  '大小',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 65 * scaleFactor,
                child: Text(
                  '创建时间',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Colors.grey),
        const SizedBox(height: 2),
        // List items
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('files_details_view'),
            controller: _detailsScrollController,
            itemCount: files.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (ctx, index) {
              final file = files[index];
              final segments = file.uri.pathSegments.where((s) => s.isNotEmpty).toList();
              final fileName = segments.isEmpty ? '未知' : segments.last;
              final (icon, iconColor) = _getFileIconAndColor(file.path);
              final stat = file.existsSync() ? file.statSync() : null;
              final sizeStr = FileSystemEntity.isDirectorySync(file.path)
                  ? '—'
                  : (stat != null ? formatFileSize(stat.size) : '—');

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
  final ThemeStyle themeStyle;

  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.showFolderBtn,
    required this.onOpenFolder,
    required this.themeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = themeStyle == ThemeStyle.compact;
    return Container(
      height: isCompact ? 26 : 32,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(isCompact ? 0 : 8),
      ),
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: isCompact ? 11 : 12),
        decoration: InputDecoration(
          hintText: '搜索暂存文件...',
          hintStyle: TextStyle(
            fontSize: isCompact ? 11 : 12,
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
                    child: AnimatedPress(
                      onTap: () => controller.clear(),
                      child: const Icon(Icons.clear, size: 15),
                    ),
                  ),
                )
              : showFolderBtn
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: onOpenFolder,
                      child: const Icon(Icons.folder_open_outlined, size: 16),
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 26,
            minHeight: 16,
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
// ══════════════════════════════════════════════════
// Reusable Delete Button with Hover Feedback
// ══════════════════════════════════════════════════
class _DeleteButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _DeleteButton({required this.onTap, required this.isDark});

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isDark ? Colors.red.withOpacity(0.24) : Colors.red.withOpacity(0.2))
                : (widget.isDark ? Colors.red.withOpacity(0.12) : Colors.red.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.close,
            size: 11,
            color: _isHovered
                ? Colors.red
                : (widget.isDark ? Colors.red[300] : Colors.red[700]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// List Card
// ══════════════════════════════════════════════════


// ══════════════════════════════════════════════════
// Grid Card
// ══════════════════════════════════════════════════
class _GridFileCard extends StatefulWidget {
  final FileSystemEntity file;
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
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final isDir = widget.file is Directory;

    final card = sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem(localData: 'internal_file_drag');
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: sdd.DraggableWidget(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                widget.onContextMenu(context, details.globalPosition),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 8),
                onTap: () {
                  final now = DateTime.now();
                  if (_lastTapTime != null &&
                      now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
                    _lastTapTime = null;
                    widget.onOpen();
                  } else {
                    _lastTapTime = now;
                  }
                },
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
                    borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 8),
                    border: Border.all(
                      color: _isHovered
                          ? (widget.isDark ? Colors.white12 : Colors.black12)
                          : Colors.transparent,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: widget.isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 6),
                                    child: Image.file(
                                      File(widget.file.path),
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
                                      borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 8),
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
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (isDir) {
      return sdd.DropRegion(
        formats: const [sdd.Formats.fileUri],
        onDropOver: (event) {
          return sdd.DropOperation.copy;
        },
        onPerformDrop: (event) async {
          final items = event.session.items;
          if (items.isEmpty) return;

          for (final item in items) {
            final reader = item.dataReader;
            if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
              reader.getValue<Uri>(sdd.Formats.fileUri, (uri) {
                if (uri != null) {
                  final sourcePath = uri.toFilePath();
                  if (item.localData == 'internal_file_drag') {
                    final sourceEntity = FileSystemEntity.isDirectorySync(sourcePath)
                        ? Directory(sourcePath)
                        : File(sourcePath);
                    AppState().moveFileToFolder(sourceEntity, Directory(widget.file.path));
                  } else {
                    AppState().addDroppedFiles([sourcePath], targetDir: Directory(widget.file.path));
                  }
                }
              });
            }
          }
        },
        child: card,
      );
    }

    return card;
  }
}

// ══════════════════════════════════════════════════
// File Preview Dialog
// ══════════════════════════════════════════════════
class _FilePreviewDialog extends StatefulWidget {
  final FileSystemEntity file;
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
      File(widget.file.path)
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
            File(widget.file.path),
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
  final FileSystemEntity file;
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
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final scaleFactor = (AppState().fileDisplaySize / 110.0).clamp(0.8, 1.4);
    final isDir = widget.file is Directory;

    final card = sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem(localData: 'internal_file_drag');
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: sdd.DraggableWidget(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                widget.onContextMenu(context, details.globalPosition),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 6),
                onTap: () {
                  final now = DateTime.now();
                  if (_lastTapTime != null &&
                      now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
                    _lastTapTime = null;
                    widget.onOpen();
                  } else {
                    _lastTapTime = now;
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.only(bottom: AppState().settings.themeStyle == ThemeStyle.compact ? 1 : 2),
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: (AppState().settings.themeStyle == ThemeStyle.compact ? 2 : 4) * scaleFactor),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? (widget.isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 6),
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 20 * scaleFactor,
                        height: 20 * scaleFactor,
                        decoration: BoxDecoration(
                          color: widget.iconColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 4),
                        ),
                        child: widget.isImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(AppState().settings.themeStyle == ThemeStyle.compact ? 0 : 4),
                                child: Image.file(
                                  File(widget.file.path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    widget.icon,
                                    size: 11 * scaleFactor,
                                    color: widget.iconColor,
                                  ),
                                ),
                              )
                            : Icon(widget.icon, size: 11 * scaleFactor, color: widget.iconColor),
                      ),
                      const SizedBox(width: 6),
                      // Name
                      Expanded(
                        child: Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11 * scaleFactor,
                            fontWeight: FontWeight.w500,
                            color: widget.isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Size
                      SizedBox(
                        width: 50 * scaleFactor,
                        child: Text(
                          widget.sizeStr,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10 * scaleFactor,
                            color: widget.isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Date
                      SizedBox(
                        width: 65 * scaleFactor,
                        child: Text(
                          widget.dateStr,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10 * scaleFactor,
                            color: widget.isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (isDir) {
      return sdd.DropRegion(
        formats: const [sdd.Formats.fileUri],
        onDropOver: (event) {
          return sdd.DropOperation.copy;
        },
        onPerformDrop: (event) async {
          final items = event.session.items;
          if (items.isEmpty) return;

          for (final item in items) {
            final reader = item.dataReader;
            if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
              reader.getValue<Uri>(sdd.Formats.fileUri, (uri) {
                if (uri != null) {
                  final sourcePath = uri.toFilePath();
                  if (item.localData == 'internal_file_drag') {
                    final sourceEntity = FileSystemEntity.isDirectorySync(sourcePath)
                        ? Directory(sourcePath)
                        : File(sourcePath);
                    AppState().moveFileToFolder(sourceEntity, Directory(widget.file.path));
                  } else {
                    AppState().addDroppedFiles([sourcePath], targetDir: Directory(widget.file.path));
                  }
                }
              });
            }
          }
        },
        child: card,
      );
    }

    return card;
  }
}
