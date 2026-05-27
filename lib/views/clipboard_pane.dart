import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../models/clipboard_item.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

class ClipboardPane extends StatefulWidget {
  final AppState state;
  final bool isDark;

  const ClipboardPane({super.key, required this.state, required this.isDark});

  @override
  State<ClipboardPane> createState() => _ClipboardPaneState();
}

class _ClipboardPaneState extends State<ClipboardPane> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.state.searchClipboardQuery;
    _searchController.addListener(() {
      widget.state.searchClipboardQuery = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.filteredClipboardHistory;
    final accentColor = AppTheme.getAccentColor(
      widget.state.settings.themeColorName,
      widget.isDark,
    );

    return Padding(
      padding: const EdgeInsets.only(
        top: 4.0,
        bottom: 4.0,
        left: 4.0,
        right: 4.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field (Header integrated) with Scroll Listener
          Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent &&
                  pointerSignal.scrollDelta.dy < 0) {
                widget.state.collapsePanel();
              }
            },
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: '搜索剪贴板记录...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: widget.isDark
                        ? Colors.white30
                        : Colors.black.withOpacity(0.3),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8.0, right: 6.0),
                    child: Icon(
                      Icons.search_rounded,
                      size: 14,
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.5)
                          : Colors.black.withOpacity(0.5),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 14,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            icon: const Icon(Icons.clear, size: 12),
                            onPressed: () => _searchController.clear(),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        )
                      : (items.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 14,
                                  ),
                                  tooltip: '清空历史（保留固定项）',
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  onPressed: () async {
                                    widget.state.setDialogOpen(true);
                                    await showDialog(
                                      context: context,
                                      barrierColor: Colors.transparent,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('清空剪贴板历史？'),
                                        content: const Text(
                                          '这将删除历史中所有未固定的记录，此操作不可撤销。',
                                        ),
                                        actions: [
                                          TextButton(
                                            child: const Text('取消'),
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                          ),
                                          TextButton(
                                            child: const Text('立即清空'),
                                            onPressed: () {
                                              widget.state
                                                  .clearClipboardHistory();
                                              setState(() {});
                                              Navigator.of(ctx).pop();
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                    widget.state.setDialogOpen(false);
                                  },
                                ),
                              )
                            : null),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 12,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // History List
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isNotEmpty ? '没有找到匹配项' : '剪贴板历史为空',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDark
                            ? Colors.white30
                            : Colors.black.withOpacity(0.3),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: items.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = items[index];

                      return ClipboardItemCard(
                        key: ValueKey(item.id),
                        item: item,
                        isDark: widget.isDark,
                        accentColor: accentColor,
                        onCopy: () =>
                            widget.state.copyToClipboard(item.content),
                        onPinToggle: () =>
                            widget.state.togglePinClipboardItem(item.id),
                        onDelete: () {
                          widget.state.deleteClipboardItem(item.id);
                          // Deferred rebuild — card hides instantly via its own state
                          Future.delayed(Duration.zero, () {
                            if (mounted) setState(() {});
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ClipboardItemCard extends StatefulWidget {
  final ClipboardItem item;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onCopy;
  final VoidCallback onPinToggle;
  final VoidCallback onDelete;

  const ClipboardItemCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.onCopy,
    required this.onPinToggle,
    required this.onDelete,
  });

  @override
  State<ClipboardItemCard> createState() => _ClipboardItemCardState();
}

class _ClipboardItemCardState extends State<ClipboardItemCard> {
  bool _isHovered = false;
  bool _isCopied = false;
  late bool _isPinned;
  bool _isDeleted = false;

  Widget _buildAppIcon() {
    final iconPath = widget.item.appIconPath;
    if (iconPath != null && iconPath.isNotEmpty) {
      final file = File(iconPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: 14,
          height: 14,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.article_outlined,
            size: 14,
            color: widget.isDark ? Colors.white30 : Colors.black38,
          ),
        );
      }
    }
    return Icon(
      Icons.article_outlined,
      size: 14,
      color: widget.isDark ? Colors.white30 : Colors.black38,
    );
  }

  @override
  void initState() {
    super.initState();
    _isPinned = widget.item.isPinned;
  }

  @override
  void didUpdateWidget(covariant ClipboardItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _isPinned = widget.item.isPinned;
  }

  void _showAllContentDialog(BuildContext context) async {
    final themeAccent = widget.accentColor;
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;
    final timeStr = DateFormat('HH:mm:ss').format(widget.item.timestamp);

    AppState().setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Dialog(
        backgroundColor: bgColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '剪贴板内容详情 ($timeStr)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Icon(Icons.close, size: 14, color: subColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: widget.isDark ? Colors.white12 : Colors.black12,
              ),
              const SizedBox(height: 8),

              // Content
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.02)
                        : Colors.black.withOpacity(0.01),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                       color: widget.isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: SelectableText(
                      widget.item.content,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Footer actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '关闭',
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        widget.onCopy();
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: themeAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '复制并关闭',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    AppState().setDialogOpen(false);
  }

  void _handleTap() {
    if (_isCopied) {
      _showAllContentDialog(context);
      return;
    }
    widget.onCopy();
    setState(() => _isCopied = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  void _handlePinToggle() {
    setState(() => _isPinned = !_isPinned);
    widget.onPinToggle();
  }

  void _handleDelete() {
    setState(() => _isDeleted = true);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleted) return const SizedBox.shrink();

    final themeAccent = widget.accentColor;

    return MouseRegion(
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
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isCopied ? themeAccent.withOpacity(0.35) : Colors.transparent,
              width: 1,
            ),
            gradient: _isCopied
                ? LinearGradient(
                    colors: [
                      themeAccent.withOpacity(0.16),
                      themeAccent.withOpacity(0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: !_isCopied && _isHovered
                ? (widget.isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.03))
                : Colors.transparent,
            boxShadow: _isCopied
                ? [
                    BoxShadow(
                      color: themeAccent.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: widget.item.appName ?? '未知应用',
                  child: _buildAppIcon(),
                ),
              ),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _isPinned ? FontWeight.w500 : FontWeight.normal,
                    color: _isCopied
                        ? themeAccent
                        : (widget.isDark ? Colors.white70 : Colors.black87),
                  ),
                  child: Text(
                    widget.item.content.trim().replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Fixed-width right section — no layout shift
              SizedBox(
                width: 78,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    );
                  },
                  child: _isCopied
                      ? SizedBox(
                          height: 24,
                          child: Row(
                            key: const ValueKey('copied_indicator'),
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: themeAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已复制',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: themeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: 24,
                          child: Row(
                            key: const ValueKey('normal_actions'),
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _IconActionButton(
                                icon: Icons.info_outline,
                                iconColor: widget.isDark ? Colors.white60 : Colors.black54,
                                hoverBgColor: widget.isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : Colors.black.withOpacity(0.1),
                                visible: _isHovered,
                                isDark: widget.isDark,
                                onTap: () => _showAllContentDialog(context),
                              ),
                              _IconActionButton(
                                icon: _isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                iconColor: _isPinned
                                    ? Colors.orange
                                    : (widget.isDark ? Colors.white60 : Colors.black54),
                                hoverBgColor: widget.isDark
                                    ? Colors.orange.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.1),
                                visible: _isHovered || _isPinned,
                                isDark: widget.isDark,
                                onTap: _handlePinToggle,
                              ),
                              _IconActionButton(
                                icon: Icons.close,
                                iconColor: widget.isDark
                                    ? Colors.red.withOpacity(0.7)
                                    : Colors.red,
                                hoverBgColor: widget.isDark
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.1),
                                visible: _isHovered,
                                isDark: widget.isDark,
                                onTap: _handleDelete,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Reusable icon button with independent hover highlight
// ══════════════════════════════════════════════════
class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color hoverBgColor;
  final bool visible;
  final bool isDark;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.iconColor,
    required this.hoverBgColor,
    required this.visible,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hovered = true);
        });
      },
      onExit: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hovered = false);
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.visible ? widget.iconColor : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
