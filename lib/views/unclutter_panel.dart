import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../services/app_state.dart';
import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import 'clipboard_pane.dart';
import 'files_pane.dart';
import 'notes_pane.dart';
import 'settings_dialog.dart';

class UnclutterPanel extends StatefulWidget {
  final AppState state;

  const UnclutterPanel({super.key, required this.state});

  @override
  State<UnclutterPanel> createState() => _UnclutterPanelState();
}

class _UnclutterPanelState extends State<UnclutterPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  Timer? _hoverTimer;
  Timer? _autoCollapseTimer;
  bool _isMouseInside = false;

  @override
  void initState() {
    super.initState();

    // Smooth macOS-style quick slide-down curve
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, -1), // Starts fully hidden above screen
          end: Offset.zero, // Slides down to fill view
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    // Listen to animation status to finalize native window collapse
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (!widget.state.isExpanded) {
          widget.state.onCollapseAnimationFinished();
        }
      }
    });

    widget.state.addListener(_handleStateChange);

    // Sync initial state
    if (widget.state.isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_handleStateChange);
    _animationController.dispose();
    _hoverTimer?.cancel();
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  void _handleStateChange() {
    if (widget.state.isExpanded) {
      if (_animationController.status != AnimationStatus.forward &&
          _animationController.status != AnimationStatus.completed) {
        _animationController.forward();
      }
    } else {
      if (_animationController.status != AnimationStatus.reverse &&
          _animationController.status != AnimationStatus.dismissed) {
        _animationController.reverse();
      }
    }
  }

  // --- Hover Activation Logic ---
  void _onMouseEnteredTopStrip() {
    if (widget.state.isExpanded || widget.state.isAnimating) return;
    if (widget.state.settings.triggerMode == TriggerMode.hotkeyOnly ||
        widget.state.settings.triggerMode == TriggerMode.scrollOnly)
      return;

    // Start timer for hover activation
    _hoverTimer?.cancel();
    _hoverTimer = Timer(
      Duration(milliseconds: widget.state.settings.hoverTimeoutMs),
      () {
        widget.state.expandPanel();
      },
    );
  }

  void _onMouseExitedTopStrip() {
    _hoverTimer?.cancel();
  }

  // 鼠标移出展开的面板窗口时开始倒计时自动收起
  void _onMouseEnteredPanel() {
    _isMouseInside = true;
    _autoCollapseTimer?.cancel();
  }

  void _onMouseExitedPanel() {
    _isMouseInside = false;
    _autoCollapseTimer?.cancel();
    if (widget.state.isDialogOpen) return;
    final delay = widget.state.settings.autoCollapseDelay;
    if (delay <= 0) return;
    if (!widget.state.isExpanded || widget.state.isAnimating) return;
    _autoCollapseTimer = Timer(Duration(seconds: delay), () {
      if (widget.state.isExpanded && !widget.state.isAnimating) {
        widget.state.collapsePanel();
      }
    });
  }

  // 顶部感应条/把手双向滚轮处理：上滑收起 / 下滑展开
  void _handleTopScrollSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    final dy = event.scrollDelta.dy;

    if (dy > 0) {
      // 下滑 → 展开 / 取消正在进行的收起动画
      if (widget.state.settings.triggerMode == TriggerMode.hotkeyOnly ||
          widget.state.settings.triggerMode == TriggerMode.hoverOnly) {
        return;
      }
      _hoverTimer?.cancel();
      if (widget.state.isAnimating && !widget.state.isExpanded) {
        // 正在收起中，反向展开
        widget.state.cancelCollapseAndExpand();
      } else if (!widget.state.isExpanded && !widget.state.isAnimating) {
        // 完全收起状态，展开
        widget.state.expandPanel();
      }
    } else if (dy < 0) {
      // 上滑 → 收起
      _hoverTimer?.cancel(); // 向上滚动时取消悬浮延迟展开，避免误触展开
      if (widget.state.isExpanded && !widget.state.isAnimating) {
        widget.state.collapsePanel();
      }
    }
  }

  // Show settings popup — temporarily expand the native window so the dialog is not clipped
  void _showSettings() async {
    final double panelW = widget.state.settings.panelWidth;
    const double expandedH = 350.0;
    const double dialogH = 620.0;

    // Expand window height to fit the dialog
    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenWidth = primaryDisplay.size.width;
      final x = (screenWidth - panelW) / 2;
      await windowManager.setBounds(Rect.fromLTWH(x, 0, panelW, dialogH));
    } catch (_) {}

    if (!mounted) return;

    // Prevent auto-collapse while settings dialog is open
    widget.state.setDialogOpen(true);
    _autoCollapseTimer?.cancel();

    await showDialog(
      context: context,
      builder: (context) => SettingsDialog(state: widget.state),
    );

    widget.state.setDialogOpen(false);

    // Restore normal window height after dialog closes
    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenWidth = primaryDisplay.size.width;
      final x = (screenWidth - panelW) / 2;
      await windowManager.setBounds(Rect.fromLTWH(x, 0, panelW, expandedH));
    } catch (_) {}

    // Check if we need to auto-collapse since settings is closed and mouse might be outside
    if (!_isMouseInside) {
      _onMouseExitedPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final isDark = widget.state.settings.isDarkTheme;
        final theme = AppTheme.getThemeData(
          isDark,
          widget.state.settings.themeColorName,
        );

        // Background and layout styling configurations
        final baseColor = isDark ? Colors.white : Colors.black;
        final dividerColor = isDark ? Colors.white10 : Colors.black12;

        return Theme(
          data: theme,
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                if (widget.state.isExpanded && !widget.state.isAnimating) {
                  widget.state.collapsePanel();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: MouseRegion(
                // 包裹整个窗口区域，鼠标移出窗口时触发 onExit
                // 注意：这里不调用 setState，仅操作 Timer，不会引起 mouse_tracker 断言
                onEnter: (_) => _onMouseEnteredPanel(),
                onExit: (_) => _onMouseExitedPanel(),
                child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Sliding Panel Box
                  OverflowBox(
                    minHeight: 350,
                    maxHeight: 350,
                    alignment: Alignment.topCenter,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Container(
                          height: 350,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: AppTheme.getFrostedDecoration(
                            isDark: isDark,
                          ),

                          child: Column(
                            children: [
                              // Main Columns Content
                              Expanded(
                                child: Row(
                                  children: [
                                    // Pane 1: Clipboard
                                    Expanded(
                                      child: ClipboardPane(
                                        state: widget.state,
                                        isDark: isDark,
                                      ),
                                    ),
                                    VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: dividerColor,
                                    ),
                                    // Pane 2: Files Dropzone
                                    Expanded(
                                      child: FilesPane(
                                        state: widget.state,
                                        isDark: isDark,
                                      ),
                                    ),
                                    VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: dividerColor,
                                    ),
                                    // Pane 3: Notes
                                    Expanded(
                                      child: NotesPane(
                                        state: widget.state,
                                        isDark: isDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Divider above bottom bar
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: dividerColor,
                              ),

                              // Bottom Tiny Control Bar
                              Container(
                                height: 24,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Left: Settings Button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.settings_outlined,
                                        size: 13,
                                      ),
                                      onPressed: _showSettings,
                                      tooltip: '设置',
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),

                                    // Center: Grab Handle / Close indicator (tap to collapse)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => widget.state.collapsePanel(),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          width: 80,
                                          height: 24,
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 36,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: baseColor.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(
                                                2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Right: Theme Toggle
                                    IconButton(
                                      icon: Icon(
                                        isDark
                                            ? Icons.light_mode_outlined
                                            : Icons.dark_mode_outlined,
                                        size: 13,
                                      ),
                                      onPressed: () {
                                        widget.state.updateSettings(
                                          widget.state.settings.copyWith(
                                            isDarkTheme: !isDark,
                                          ),
                                        );
                                      },
                                      tooltip: '切换主题',
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ),
                  ),

                  // 2. 收起时显示的悬浮条：Windows上为 3px 的横杠，macOS上为 24px 透明层以捕获顶部系统状态栏的滚轮事件
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: Platform.isMacOS ? 24.0 : 3.0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => _onMouseEnteredTopStrip(),
                      onExit: (_) => _onMouseExitedTopStrip(),
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: _handleTopScrollSignal, // 直接复用统一方法
                        child: Container(
                          color: Platform.isMacOS
                              ? Colors.transparent
                              : (isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.black.withOpacity(0.05)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),         // Stack
            ),           // MouseRegion (body)
          ),             // Scaffold
        ),               // Focus
      );
      },
    );
  }
}
