import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;
import '../services/app_state.dart';
import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import 'clipboard_pane.dart';
import 'files_pane.dart';
import 'notes_pane.dart';
import 'settings_dialog.dart';

class PodPanel extends StatefulWidget {
  final AppState state;

  const PodPanel({super.key, required this.state});

  @override
  State<PodPanel> createState() => _PodPanelState();
}

class _PodPanelState extends State<PodPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  Timer? _hoverTimer;
  bool _isMouseInside = false;
  bool _isDragDropReady = false;

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
    _animationController.addStatusListener((status) async {
      if (status == AnimationStatus.completed) {
        if (Platform.isMacOS) {
          await windowManager.setIgnoreMouseEvents(false);
        }
      } else if (status == AnimationStatus.dismissed) {
        if (!widget.state.isExpanded) {
          widget.state.onCollapseAnimationFinished();
        }
      }
    });

    widget.state.onAnimationStateChanged = _handleStateChange;

    // Sync initial state
    if (widget.state.isExpanded) {
      _animationController.value = 1.0;
    }

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
    widget.state.onAnimationStateChanged = null;
    _animationController.dispose();
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _handleStateChange(Duration duration) {
    if (widget.state.isExpanded) {
      if (duration == Duration.zero) {
        _animationController.value = 1.0;
      } else {
        _animationController.duration = duration;
        if (_animationController.status != AnimationStatus.forward &&
            _animationController.status != AnimationStatus.completed) {
          _animationController.forward();
        }
      }
    } else {
      _isMouseInside = false;
      widget.state.isMouseInside = false;
      if (duration == Duration.zero) {
        _animationController.value = 0.0;
        if (!widget.state.isExpanded) {
          widget.state.onCollapseAnimationFinished();
        }
      } else {
        _animationController.duration = duration;
        if (_animationController.status != AnimationStatus.reverse &&
            _animationController.status != AnimationStatus.dismissed) {
          _animationController.reverse();
        }
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
    widget.state.isMouseInside = true; // Sync to AppState
    widget.state.cancelAutoCollapseTimer();
  }

  void _onMouseExitedPanel() {
    _isMouseInside = false;
    widget.state.isMouseInside = false; // Sync to AppState
    widget.state.startAutoCollapseTimer();
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
    const double expandedH = 350.0;
    const double dialogH = 620.0;

    final screenInfo = await widget.state.getActiveScreenInfo();
    final double screenWidth = screenInfo['width']!;
    final double screenX = screenInfo['x']!;
    final double menuBarHeight = screenInfo['visibleY']!;

    // 使用已缓存的面板宽度，避免重复计算
    final double panelW = widget.state.lastCalculatedWidth;

    // 展开窗口高度以容纳设置弹窗
    final x = screenX + (screenWidth - panelW) / 2;
    await windowManager.setBounds(
      Rect.fromLTWH(x, menuBarHeight, panelW, dialogH),
    );

    if (!mounted) return;

    // 打开期间禁止自动收起
    widget.state.setDialogOpen(true);
    widget.state.cancelAutoCollapseTimer();

    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => SettingsDialog(state: widget.state),
    );

    widget.state.setDialogOpen(false);

    // 弹窗关闭后：直接用 lastCalculatedWidth（updateSettings 已更新）
    final double updatedPanelW = widget.state.lastCalculatedWidth;
    final rx = screenX + (screenWidth - updatedPanelW) / 2;
    await windowManager.setBounds(
      Rect.fromLTWH(rx, menuBarHeight, updatedPanelW, expandedH),
    );

    // 设置关闭后若鼠标不在面板内，启动自动收起计时器
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

        return AnimatedTheme(
          data: theme,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: Builder(
            builder: (context) {
              final currentTheme = Theme.of(context);
              final dividerColor = currentTheme.dividerColor;
              final animatedIsDark = currentTheme.brightness == Brightness.dark;

              return Focus(
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
                          minWidth: widget.state.lastCalculatedWidth,
                          maxWidth: widget.state.lastCalculatedWidth,
                          minHeight: 350,
                          maxHeight: 350,
                          alignment: Alignment.topCenter,
                          child: ClipRect(
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: RepaintBoundary(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  height: 350,
                                  margin: (widget.state.settings.themeStyle ==
                                              ThemeStyle.compact ||
                                          (widget.state.settings.isWidthPercentage &&
                                              widget.state.settings
                                                      .panelWidthPercent >=
                                                  100))
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.symmetric(
                                          horizontal: 6),
                                  decoration: AppTheme.getFrostedDecoration(
                                    isDark: animatedIsDark,
                                    themeStyle:
                                        widget.state.settings.themeStyle,
                                    color: currentTheme.scaffoldBackgroundColor
                                        .withOpacity(widget
                                            .state.settings.backdropOpacity),
                                    borderColor: currentTheme.colorScheme.outline,
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
                                                isDark: animatedIsDark,
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
                                                isDark: animatedIsDark,
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
                                                isDark: animatedIsDark,
                                                onShowSettings: _showSettings,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!Platform.isMacOS) ...[
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: dividerColor,
                                        ),
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
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: EdgeInsets.zero,
                                              ),

                                              // Center: Grab Handle / Close indicator (tap to collapse)
                                              GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () => widget.state
                                                    .collapsePanel(),
                                                child: MouseRegion(
                                                  cursor:
                                                      SystemMouseCursors.click,
                                                  child: Container(
                                                    width: 80,
                                                    height: 24,
                                                    alignment: Alignment.center,
                                                    child: Container(
                                                      width: 36,
                                                      height: 4,
                                                      decoration: BoxDecoration(
                                                        color: (animatedIsDark
                                                                ? Colors.white
                                                                : Colors.black)
                                                            .withOpacity(0.25),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                2),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              // Right: Theme Toggle
                                              IconButton(
                                                icon: Icon(
                                                  animatedIsDark
                                                      ? Icons
                                                          .light_mode_outlined
                                                      : Icons
                                                          .dark_mode_outlined,
                                                  size: 13,
                                                ),
                                                onPressed: () {
                                                  widget.state.updateSettings(
                                                    widget.state.settings
                                                        .copyWith(
                                                      isDarkTheme:
                                                          !animatedIsDark,
                                                    ),
                                                  );
                                                },
                                                tooltip: '切换主题',
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 2. Collapsed top strip for Windows/Linux.
                        if (!Platform.isMacOS)
                          Positioned(
                            top: 0.0,
                            left: 0,
                            right: 0,
                            height: 3.0,
                            child: _isDragDropReady
                                ? sdd.DropRegion(
                                    formats: const [sdd.Formats.fileUri],
                                    onDropEnter: (event) {
                                      final isInternal = event.session.items
                                          .any((item) =>
                                              item.localData ==
                                              'internal_file_drag');
                                      if (isInternal) return;
                                      if (!widget.state.isExpanded &&
                                          !widget.state.isAnimating) {
                                        widget.state.expandPanel();
                                      }
                                    },
                                    onDropOver: (event) {
                                      final isInternal = event.session.items
                                          .any((item) =>
                                              item.localData ==
                                              'internal_file_drag');
                                      return isInternal
                                          ? sdd.DropOperation.none
                                          : sdd.DropOperation.copy;
                                    },
                                    onPerformDrop: (event) async {
                                      // No-op
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      onEnter: (_) => _onMouseEnteredTopStrip(),
                                      onExit: (_) => _onMouseExitedTopStrip(),
                                      child: Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerSignal:
                                            _handleTopScrollSignal, // 直接复用统一方法
                                        child: Container(
                                          color: Platform.isMacOS
                                              ? Colors.white.withOpacity(0.01)
                                              : (animatedIsDark
                                                  ? Colors.white
                                                      .withOpacity(0.1)
                                                  : Colors.black
                                                      .withOpacity(0.05)),
                                        ),
                                      ),
                                    ),
                                  )
                                : MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => _onMouseEnteredTopStrip(),
                                    onExit: (_) => _onMouseExitedTopStrip(),
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerSignal:
                                          _handleTopScrollSignal, // 直接复用统一方法
                                      child: Container(
                                        color: Platform.isMacOS
                                            ? Colors.white.withOpacity(0.01)
                                            : (animatedIsDark
                                                ? Colors.white.withOpacity(0.1)
                                                : Colors.black
                                                    .withOpacity(0.05)),
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ), // Stack
                  ), // MouseRegion (body)
                ), // Scaffold
              ); // Focus
            },
          ), // Builder
        ); // AnimatedTheme
      },
    );
  }
}
