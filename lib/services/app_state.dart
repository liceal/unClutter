import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:uuid/uuid.dart';

import '../models/clipboard_item.dart';
import '../models/note.dart';
import '../models/app_settings.dart';

class AppState extends ChangeNotifier with WindowListener, TrayListener {
  static const _clipboardOwnerChannel = MethodChannel(
    'app.pod/clipboard_owner',
  );

  static const _menuBarScrollChannel = MethodChannel('app.pod/menu_bar_scroll');

  static const _focusManagerChannel = MethodChannel('app.pod/focus_manager');

  // Singleton
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final _uuid = const Uuid();
  late SharedPreferences _prefs;

  // State Variables
  AppSettings settings = AppSettings();
  List<ClipboardItem> clipboardHistory = [];
  List<ClipboardItem> clipboardFavorites = [];
  List<FileSystemEntity> storedFiles = [];
  List<Note> notes = [];
  Note? activeNote;

  bool isExpanded = false;
  bool isAnimating = false;
  bool isDialogOpen = false;
  bool isMouseInside = false;
  double lastCalculatedWidth = 800.0;
  double fileDisplaySize = 110.0;

  String _searchClipboardQuery = '';
  String _searchNotesQuery = '';

  String _lastSystemClipText = '';
  String _lastAppCopiedText = '';
  Timer? _clipboardTimer;
  Timer? _notesSaveTimer;
  Timer? _autoCollapseTimer;

  String _trayIconPath = '';
  StreamSubscription<FileSystemEvent>? _dirWatcher;

  bool _didGrabFocus = false;
  Display? _currentDisplay;
  Map<String, double>? _nativeScreenInfo;
  DateTime _lastScrollAction = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastExpandedScreenX = -1;

  // Lightweight callback for animation-only updates
  void Function(Duration duration)? onAnimationStateChanged;

  /// Get the display where the mouse cursor currently is
  Future<Display> _getCurrentDisplay() async {
    try {
      final cursorPoint = await screenRetriever.getCursorScreenPoint();
      final displays = await screenRetriever.getAllDisplays();
      for (final display in displays) {
        final pos = display.visiblePosition ?? Offset.zero;
        final size = display.visibleSize ?? display.size;
        final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
        if (rect.contains(cursorPoint)) {
          return display;
        }
      }
    } catch (e) {
      debugPrint('Failed to get current display: $e');
    }
    return await screenRetriever.getPrimaryDisplay();
  }

  /// Get the active screen dimensions and position containing the mouse cursor
  Future<Map<String, double>> getActiveScreenInfo() async {
    final display = await _getCurrentDisplay();
    final double sw = display.size.width;
    final double sx = (display.visiblePosition ?? Offset.zero).dx;
    final double sy = (display.visiblePosition ?? Offset.zero).dy;
    return {'x': sx, 'width': sw, 'visibleY': sy};
  }

  bool isItemFavorite(String content) {
    return clipboardFavorites.any((x) => x.content == content);
  }

  List<ClipboardItem> get filteredClipboardHistory {
    if (_searchClipboardQuery.isEmpty) {
      return List.from(clipboardHistory)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardHistory
        .where((item) => item.content.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<ClipboardItem> get filteredClipboardFavorites {
    if (_searchClipboardQuery.isEmpty) {
      return List.from(clipboardFavorites)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardFavorites
        .where((item) => item.content.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<Note> get filteredNotes {
    if (_searchNotesQuery.isEmpty) {
      return List.from(notes)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    final query = _searchNotesQuery.toLowerCase();
    return notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(query) ||
              n.content.toLowerCase().contains(query),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  String get searchClipboardQuery => _searchClipboardQuery;
  set searchClipboardQuery(String value) {
    _searchClipboardQuery = value;
    notifyListeners();
  }

  String get searchNotesQuery => _searchNotesQuery;
  set searchNotesQuery(String value) {
    _searchNotesQuery = value;
    notifyListeners();
  }

  // --- Initializer ---
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    windowManager.addListener(this);
    trayManager.addListener(this);

    // Load Local Data
    _loadSettings();
    await _loadClipboardHistory();
    await _loadNotes();
    await _scanStoredFiles();

    // Setup hooks
    await _setupTray();
    await _setupHotkeys();
    _startClipboardMonitoring();

    if (Platform.isMacOS || Platform.isWindows) {
      _menuBarScrollChannel.setMethodCallHandler((call) async {
        if (call.method == 'onMenuBarScroll') {
          final args = call.arguments;
          if (args is Map) {
            final double dy = (args['dy'] as num).toDouble();
            // Capture screen info as a local snapshot to avoid race conditions
            final screenInfo = Map<String, double>.from(
              args.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
            );
            _nativeScreenInfo = screenInfo;
            _handleMenuBarScroll(dy);
          } else {
            _handleMenuBarScroll((args as num).toDouble());
          }
        }
      });
    }

    // Position window
    await windowManager.setMinimumSize(const Size(1, 1));
    await applyWindowTriggerConfiguration(isStartup: true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _clipboardTimer?.cancel();
    _notesSaveTimer?.cancel();
    _autoCollapseTimer?.cancel();
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  // --- Window Trigger Configuration ---
  Future<void> applyWindowTriggerConfiguration({
    bool isStartup = false,
    Display? targetDisplay,
  }) async {
    try {
      final display =
          targetDisplay ?? _currentDisplay ?? await _getCurrentDisplay();
      final screenWidth = display.size.width;
      final screenPosition = display.visiblePosition ?? Offset.zero;

      double w;
      if (settings.isWidthPercentage) {
        w = screenWidth * (settings.panelWidthPercent / 100.0);
      } else {
        w = settings.panelWidth;
      }
      lastCalculatedWidth = w;
      final double wCollapsed = Platform.isMacOS ? screenWidth : w;
      final double hCollapsed = Platform.isMacOS ? 350.0 : 3.0;

      if (isStartup) {
        WindowOptions windowOptions = WindowOptions(
          size: Size(wCollapsed, hCollapsed),
          backgroundColor: Colors.transparent,
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setAsFrameless();
          await windowManager.setMinimumSize(const Size(1, 1));
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setHasShadow(false);
          if (Platform.isWindows) {
            await windowManager.setIgnoreMouseEvents(false);
          }

          if (settings.triggerMode == TriggerMode.hotkeyOnly) {
            await windowManager.hide();
          } else {
            final x = screenPosition.dx + (screenWidth - wCollapsed) / 2;
            if (Platform.isMacOS) {
              // WindowOptions already set the size, just position and show
              await _menuBarScrollChannel.invokeMethod(
                'setWindowFrameOnScreen',
                {'x': x, 'y': 0.0, 'width': wCollapsed, 'height': hCollapsed},
              );
              await Future.delayed(const Duration(milliseconds: 50));
              await _menuBarScrollChannel.invokeMethod('showInactive');
            } else {
              await windowManager.setBounds(
                Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
              );
              await windowManager.show();
            }
          }
        });
      } else {
        // Collapsed state: hide or position collapsed bar
        // Only reset the native window configuration if the panel is currently collapsed.
        // If the panel is expanded (e.g. showing the settings dialog), we do not want to hide the window.
        if (!isExpanded) {
          await windowManager.setHasShadow(false);
          if (settings.triggerMode == TriggerMode.hotkeyOnly) {
            await windowManager.hide();
          } else if (Platform.isMacOS) {
            await windowManager.setIgnoreMouseEvents(true);
            await windowManager.hide();
          } else {
            // Windows: position collapsed bar on the correct screen
            final x = screenPosition.dx + (screenWidth - wCollapsed) / 2;
            await windowManager.setBounds(
              Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
            );
            await windowManager.setIgnoreMouseEvents(false);
            if (!await windowManager.isVisible()) {
              await windowManager.show();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to apply window configuration: $e');
    }
  }

  void _handleMenuBarScroll(double dy) {
    if (settings.triggerMode == TriggerMode.hotkeyOnly ||
        settings.triggerMode == TriggerMode.hoverOnly) {
      return;
    }

    if (dy > 0) {
      // Throttle expand only
      final now = DateTime.now();
      if (now.difference(_lastScrollAction).inMilliseconds < 200) return;
      _lastScrollAction = now;

      if (isAnimating && !isExpanded) {
        cancelCollapseAndExpand();
      } else if (!isExpanded && !isAnimating) {
        expandPanel(focus: true, duration: const Duration(milliseconds: 250));
      }
    } else if (dy < 0) {
      if (isExpanded && !isAnimating) {
        collapsePanel(duration: const Duration(milliseconds: 250));
      }
    }
  }

  // --- Expand / Collapse Actions ---
  Future<void> togglePanel() async {
    if (isAnimating) return;
    if (isExpanded) {
      await collapsePanel();
    } else {
      await expandPanel(focus: true);
    }
  }

  Future<void> expandPanel({
    bool focus = false,
    Duration duration = const Duration(milliseconds: 280),
  }) async {
    if (isExpanded || isAnimating) return;
    isAnimating = true;
    isExpanded = true;

    try {
      final bool shouldFocus =
          focus || settings.triggerMode == TriggerMode.hotkeyOnly;

      // Set native window FIRST, then trigger animation
      if (Platform.isMacOS) {
        final info = _nativeScreenInfo;
        if (info != null) {
          final sw = info['width']!;
          double w = settings.isWidthPercentage
              ? sw * (settings.panelWidthPercent / 100.0)
              : settings.panelWidth;
          if (lastCalculatedWidth != w) {
            lastCalculatedWidth = w;
            notifyListeners(); // Ensure Flutter UI updates to the new width immediately
          }
          final screenChanged = _lastExpandedScreenX != info['x'];
          _lastExpandedScreenX = info['x']!;
          // Move window to correct screen position (cheap)
          _menuBarScrollChannel.invokeMethod('expandOnScreen', {
            'x': info['x']! + (sw - w) / 2,
            'y': info['visibleY']!,
            'width': w,
            'height': 350.0,
            'focus': shouldFocus,
          });
          // The native window is resized immediately without display block,
          // and animated natively via CoreAnimation in MainFlutterWindow.swift.
          // This avoids Flutter timeout issues entirely and gives 60fps animations.
        }
      } else {
        final nativeInfo = _nativeScreenInfo;
        double screenX;
        double screenY;
        double screenWidth;
        if (nativeInfo != null) {
          screenX = nativeInfo['x']!;
          screenY = nativeInfo['visibleY'] ?? nativeInfo['y'] ?? 0.0;
          screenWidth = nativeInfo['width']!;
        } else {
          _currentDisplay = await _getCurrentDisplay();
          final position = _currentDisplay!.visiblePosition ?? Offset.zero;
          screenX = position.dx;
          screenY = position.dy;
          screenWidth = _currentDisplay!.size.width;
        }
        double w = settings.isWidthPercentage
            ? screenWidth * (settings.panelWidthPercent / 100.0)
            : settings.panelWidth;
        lastCalculatedWidth = w;
        await windowManager.setIgnoreMouseEvents(false);
        final targetX = screenX + (screenWidth - w) / 2;
        await windowManager.setBounds(
          Rect.fromLTWH(targetX, screenY, w, 350),
        );
        await windowManager.setHasShadow(true);
        if (shouldFocus) {
          _focusManagerChannel.invokeMethod('savePreviousApp');
          await windowManager.show();
          await windowManager.focus();
        } else {
          await windowManager.show(inactive: true);
        }
      }

      // Now trigger animation AFTER native window is ready
      onAnimationStateChanged?.call(duration);
      _didGrabFocus = shouldFocus;
    } catch (e) {
      debugPrint('Failed to expand panel: $e');
    } finally {
      isAnimating = false;
      startAutoCollapseTimer();
    }
  }

  Future<void> forceSaveNotesIfPending() async {
    if (_notesSaveTimer?.isActive ?? false) {
      _notesSaveTimer?.cancel();
      await _saveNotes();
    }
  }

  Future<void> collapsePanel({
    Duration duration = const Duration(milliseconds: 280),
  }) async {
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer?.cancel();
    isAnimating = true;
    isExpanded = false;

    if (_didGrabFocus) {
      if (Platform.isMacOS) {
        _menuBarScrollChannel.invokeMethod('restorePreviousApp');
      } else {
        _focusManagerChannel.invokeMethod('restorePreviousApp');
      }
      _didGrabFocus = false;
    }

    if (Platform.isMacOS) {
      windowManager.setIgnoreMouseEvents(true);
    }
    onAnimationStateChanged?.call(duration);

    // Save notes in background to avoid blocking focus restore and UI
    forceSaveNotesIfPending();

    // We wait for the sliding animation to complete inside the UI before resizing the native window.
    // The UI calls AppState.onCollapseAnimationFinished() to finalize this.
  }

  Future<void> onCollapseAnimationFinished() async {
    isAnimating = false;
    _currentDisplay = null;
    _nativeScreenInfo = null;

    if (!Platform.isMacOS) {
      try {
        final display = await _getCurrentDisplay();
        final screenWidth = display.size.width;
        final position = display.visiblePosition ?? Offset.zero;
        final x = position.dx + (screenWidth - lastCalculatedWidth) / 2;
        await windowManager.setBounds(
          Rect.fromLTWH(x, position.dy, lastCalculatedWidth, 3),
        );
        await windowManager.setIgnoreMouseEvents(false);
      } catch (e) {
        debugPrint('Failed to resize collapsed window: $e');
      }
    }
  }

  void cancelCollapseAndExpand() {
    if (!isExpanded) {
      isExpanded = true;
      isAnimating = false;
      onAnimationStateChanged?.call(const Duration(milliseconds: 250));
    }
  }

  void setDialogOpen(bool open) {
    isDialogOpen = open;
    notifyListeners();
  }

  void updateFileDisplaySize(double value) {
    fileDisplaySize = value;
    notifyListeners();
  }

  void startAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    if (isDialogOpen || isMouseInside) return;
    final delay = settings.autoCollapseDelay;
    if (delay <= 0) return;
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer = Timer(Duration(seconds: delay), () {
      if (isExpanded && !isAnimating) {
        collapsePanel();
      }
    });
  }

  void cancelAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
  }

  // --- Window Listeners ---
  @override
  void onWindowBlur() {
    // 失去焦点时启动自动收起计时器
    if (Platform.isMacOS) {
      startAutoCollapseTimer();
    }
    // User clicked away — don't restore focus when auto-collapsing later
    _didGrabFocus = false;
  }

  @override
  void onWindowFocus() {
    // Cancel auto-collapse timer when window is focused
    cancelAutoCollapseTimer();
  }

  // --- Settings Persistence ---
  void _loadSettings() {
    final settingsJson = _prefs.getString('settings');
    if (settingsJson != null) {
      try {
        settings = AppSettings.fromJson(jsonDecode(settingsJson));
      } catch (e) {
        settings = AppSettings();
      }
    } else {
      settings = AppSettings();
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    final oldPath = settings.customFilesPath;
    settings = newSettings;
    await _prefs.setString('settings', jsonEncode(settings.toJson()));

    // Reconfigure hooks & window positions
    await _setupHotkeys();
    await applyWindowTriggerConfiguration();

    if (oldPath != newSettings.customFilesPath) {
      await _scanStoredFiles();
    }
    notifyListeners();
  }

  PhysicalKeyboardKey? _getPhysicalKey(String name) {
    final cleanName = name.trim().toLowerCase();
    if (cleanName == 'space') return PhysicalKeyboardKey.space;
    final letterMap = {
      'a': PhysicalKeyboardKey.keyA,
      'b': PhysicalKeyboardKey.keyB,
      'c': PhysicalKeyboardKey.keyC,
      'd': PhysicalKeyboardKey.keyD,
      'e': PhysicalKeyboardKey.keyE,
      'f': PhysicalKeyboardKey.keyF,
      'g': PhysicalKeyboardKey.keyG,
      'h': PhysicalKeyboardKey.keyH,
      'i': PhysicalKeyboardKey.keyI,
      'j': PhysicalKeyboardKey.keyJ,
      'k': PhysicalKeyboardKey.keyK,
      'l': PhysicalKeyboardKey.keyL,
      'm': PhysicalKeyboardKey.keyM,
      'n': PhysicalKeyboardKey.keyN,
      'o': PhysicalKeyboardKey.keyO,
      'p': PhysicalKeyboardKey.keyP,
      'q': PhysicalKeyboardKey.keyQ,
      'r': PhysicalKeyboardKey.keyR,
      's': PhysicalKeyboardKey.keyS,
      't': PhysicalKeyboardKey.keyT,
      'u': PhysicalKeyboardKey.keyU,
      'v': PhysicalKeyboardKey.keyV,
      'w': PhysicalKeyboardKey.keyW,
      'x': PhysicalKeyboardKey.keyX,
      'y': PhysicalKeyboardKey.keyY,
      'z': PhysicalKeyboardKey.keyZ,
      '0': PhysicalKeyboardKey.digit0,
      '1': PhysicalKeyboardKey.digit1,
      '2': PhysicalKeyboardKey.digit2,
      '3': PhysicalKeyboardKey.digit3,
      '4': PhysicalKeyboardKey.digit4,
      '5': PhysicalKeyboardKey.digit5,
      '6': PhysicalKeyboardKey.digit6,
      '7': PhysicalKeyboardKey.digit7,
      '8': PhysicalKeyboardKey.digit8,
      '9': PhysicalKeyboardKey.digit9,
    };
    return letterMap[cleanName];
  }

  Future<void> _setupHotkeys() async {
    await hotKeyManager.unregisterAll();
    if (settings.triggerMode == TriggerMode.hoverOnly ||
        settings.triggerMode == TriggerMode.scrollOnly) {
      return;
    }

    PhysicalKeyboardKey? key;
    List<HotKeyModifier> modifiers = [];

    final parts = settings.hotkey.toLowerCase().split('+');
    for (var part in parts) {
      if (part == 'alt') {
        modifiers.add(HotKeyModifier.alt);
      } else if (part == 'ctrl' || part == 'control') {
        modifiers.add(HotKeyModifier.control);
      } else if (part == 'shift') {
        modifiers.add(HotKeyModifier.shift);
      } else if (part == 'meta' || part == 'win' || part == 'command') {
        modifiers.add(HotKeyModifier.meta);
      } else {
        key = _getPhysicalKey(part);
      }
    }

    key ??= PhysicalKeyboardKey.keyU;
    if (modifiers.isEmpty) modifiers.add(HotKeyModifier.alt);

    HotKey hotkey = HotKey(
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.system, // Global shortcut
    );

    await hotKeyManager.register(
      hotkey,
      keyDownHandler: (hotKey) {
        togglePanel();
      },
    );
  }

  // --- System Tray ---
  Future<void> _setupTray() async {
    try {
      if (Platform.isWindows) {
        _trayIconPath = 'assets/images/tray_icon.ico';
      } else {
        _trayIconPath = 'assets/images/tray_icon.png';
      }
      await trayManager.setIcon(_trayIconPath);
    } catch (e) {
      debugPrint('Failed to set tray icon: $e');
    }

    final menuItems = [
      MenuItem(key: 'toggle', label: '显示/隐藏 Pod'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ];
    await trayManager.setContextMenu(Menu(items: menuItems));
    await trayManager.setToolTip('Pod 助手');
  }

  @override
  void onTrayIconMouseDown() {
    togglePanel();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'toggle') {
      togglePanel();
    } else if (menuItem.key == 'quit') {
      windowManager.destroy();
    }
  }

  // --- Clipboard History ---
  void _startClipboardMonitoring() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // Only monitor clipboard when app is NOT expanding/showing its own copies to avoid duplicate history logs
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data != null && data.text != null && data.text!.isNotEmpty) {
          final text = data.text!;
          if (text != _lastSystemClipText) {
            _lastSystemClipText = text;

            // If the user copied this text from the app itself, don't add duplicate
            if (text != _lastAppCopiedText) {
              String? appName;
              String? appIconPath;

              if (Platform.isWindows || Platform.isMacOS) {
                try {
                  final result = await _clipboardOwnerChannel.invokeMethod(
                    'getClipboardOwner',
                  );
                  if (result is Map) {
                    appName = result['name'] as String?;
                    appIconPath = result['iconPath'] as String?;
                  }
                } catch (e) {
                  debugPrint('Failed to get clipboard owner info: $e');
                }
              }

              await addClipboardItem(
                text,
                appName: appName,
                appIconPath: appIconPath,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Clipboard monitoring error: $e');
      }
    });
  }

  Future<void> addClipboardItem(
    String content, {
    String? appName,
    String? appIconPath,
  }) async {
    // Avoid duplicates of the exact same content in recent clipboard history list
    clipboardHistory.removeWhere((item) => item.content == content);

    final newItem = ClipboardItem(
      id: _uuid.v4(),
      content: content,
      timestamp: DateTime.now(),
      appName: appName,
      appIconPath: appIconPath,
    );

    clipboardHistory.insert(0, newItem);

    // Limit size
    if (clipboardHistory.length > 50) {
      clipboardHistory.removeLast();
    }

    await _saveClipboardHistory();
    notifyListeners();
  }

  Future<void> copyToClipboard(String content) async {
    _lastAppCopiedText = content;
    _lastSystemClipText = content; // Keep sync
    await Clipboard.setData(ClipboardData(text: content));
  }

  void deleteClipboardItem(String id) {
    clipboardHistory.removeWhere((item) => item.id == id);
    clipboardFavorites.removeWhere((item) => item.id == id);
    Future.delayed(Duration.zero, () {
      _saveClipboardHistory();
      _saveClipboardFavorites();
    });
    notifyListeners();
  }

  void toggleFavoriteClipboardItem(ClipboardItem item) {
    final isFav = isItemFavorite(item.content);
    if (isFav) {
      clipboardFavorites.removeWhere((x) => x.content == item.content);
    } else {
      clipboardFavorites.insert(
        0,
        item.copyWith(isFavorite: true, timestamp: DateTime.now()),
      );
    }
    Future.delayed(Duration.zero, _saveClipboardFavorites);
    notifyListeners();
  }

  void clearClipboardHistory() {
    clipboardHistory.clear();
    Future.delayed(Duration.zero, _saveClipboardHistory);
    notifyListeners();
  }

  Future<void> _loadClipboardHistory() async {
    final listJson = _prefs.getString('clipboard_history');
    if (listJson != null) {
      try {
        final decoded = jsonDecode(listJson) as List;
        clipboardHistory = decoded
            .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        clipboardHistory = [];
      }
    }
    final favJson = _prefs.getString('clipboard_favorites');
    if (favJson != null) {
      try {
        final decoded = jsonDecode(favJson) as List;
        clipboardFavorites = decoded
            .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        clipboardFavorites = [];
      }
    }
  }

  Future<void> _saveClipboardHistory() async {
    final encoded = jsonEncode(
      clipboardHistory.map((item) => item.toJson()).toList(),
    );
    await _prefs.setString('clipboard_history', encoded);
  }

  Future<void> _saveClipboardFavorites() async {
    final encoded = jsonEncode(
      clipboardFavorites.map((item) => item.toJson()).toList(),
    );
    await _prefs.setString('clipboard_favorites', encoded);
  }

  // --- Files Storage ---
  Future<String> getFilesDirectoryPath() => _getFilesDirectoryPath();

  Future<String> _getFilesDirectoryPath() async {
    if (settings.customFilesPath != null &&
        settings.customFilesPath!.trim().isNotEmpty) {
      final customDir = Directory(settings.customFilesPath!.trim());
      if (!customDir.existsSync()) {
        try {
          customDir.createSync(recursive: true);
        } catch (e) {
          debugPrint('Failed to create custom files directory: $e');
        }
      }
      if (customDir.existsSync()) {
        return customDir.path;
      }
    }

    // 使用用户文档目录下的明显文件夹，方便用户找到
    late String basePath;
    if (Platform.isWindows) {
      // Windows: C:\Users\<用户名>\Documents\Pod暂存
      basePath = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$basePath\\Documents\\Pod暂存';
    } else if (Platform.isMacOS) {
      basePath = Platform.environment['HOME'] ?? '';
      basePath = '$basePath/Documents/Pod暂存';
    } else {
      final appSupport = await getApplicationSupportDirectory();
      basePath = '${appSupport.path}/files';
    }
    final filesDir = Directory(basePath);
    if (!filesDir.existsSync()) {
      filesDir.createSync(recursive: true);
    }
    return filesDir.path;
  }

  DateTime _getFileTime(FileSystemEntity entity) {
    try {
      if (!entity.existsSync()) return DateTime(0);
      final stat = entity.statSync();
      // On Windows, stat.changed is creation time (birth time)
      return Platform.isWindows ? stat.changed : stat.modified;
    } catch (_) {
      return DateTime(0);
    }
  }

  Future<void> _scanStoredFiles() async {
    try {
      final path = await _getFilesDirectoryPath();
      final dir = Directory(path);
      storedFiles =
          dir
              .listSync()
              .where((entity) => entity is File || entity is Directory)
              .toList()
            ..sort((a, b) {
              final timeA = _getFileTime(a);
              final timeB = _getFileTime(b);
              return timeB.compareTo(timeA);
            });
      notifyListeners();
      // 每次扫描后重新建立监听（路径可能刚刚创建）
      await _startWatchingFilesDirectory(path);
    } catch (e) {
      debugPrint('Error scanning files: $e');
    }
  }

  Future<void> _startWatchingFilesDirectory(String path) async {
    await _dirWatcher?.cancel();
    try {
      final dir = Directory(path);
      _dirWatcher = dir.watch(events: FileSystemEvent.all).listen((event) {
        // 文件夹内容变化时重新扫描（不再重建监听，避免递归）
        _rescanWithoutRebuildingWatcher();
      });
    } catch (e) {
      debugPrint('Failed to watch directory: $e');
    }
  }

  void _rescanWithoutRebuildingWatcher() {
    _getFilesDirectoryPath().then((path) {
      try {
        final dir = Directory(path);
        storedFiles =
            dir
                .listSync()
                .where((entity) => entity is File || entity is Directory)
                .toList()
              ..sort((a, b) {
                final timeA = _getFileTime(a);
                final timeB = _getFileTime(b);
                return timeB.compareTo(timeA);
              });
        notifyListeners();
      } catch (_) {}
    });
  }

  Future<void> addDroppedFiles(
    List<String> filePaths, {
    Directory? targetDir,
  }) async {
    final destPath = targetDir?.path ?? await _getFilesDirectoryPath();
    for (var filePath in filePaths) {
      try {
        if (FileSystemEntity.isDirectorySync(filePath)) {
          // If it is a directory, copy the directory recursively or copy its folder structure
          final srcDir = Directory(filePath);
          final dirName = srcDir.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          final destDir = Directory('$destPath/$dirName');
          if (!destDir.existsSync()) {
            await destDir.create(recursive: true);
          }
          // Copy files in folder (simple shallow copy for performance/safety)
          await for (final entity in srcDir.list(recursive: true)) {
            final relativePath = entity.path.substring(srcDir.path.length);
            if (entity is File) {
              final newFile = File('${destDir.path}$relativePath');
              await newFile.parent.create(recursive: true);
              await entity.copy(newFile.path);
            } else if (entity is Directory) {
              final newSubDir = Directory('${destDir.path}$relativePath');
              await newSubDir.create(recursive: true);
            }
          }
        } else {
          final srcFile = File(filePath);
          if (srcFile.existsSync()) {
            // Extract file name
            final fileName = srcFile.uri.pathSegments.last;
            final destFile = File('$destPath/$fileName');

            // Copy
            await srcFile.copy(destFile.path);

            // Preserve the original file's creation/modification time by setting the copy's last modified time
            try {
              final srcStat = srcFile.statSync();
              final creationTime = Platform.isWindows
                  ? srcStat.changed
                  : srcStat.modified;
              await destFile.setLastModified(creationTime);
            } catch (e) {
              debugPrint(
                'Failed to set last modified time for copied file: $e',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to copy file: $e');
      }
    }
    await _scanStoredFiles();
  }

  Future<void> deleteFile(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) {
        await entity.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to delete file: $e');
    }
    await _scanStoredFiles();
  }

  Future<void> openFile(FileSystemEntity entity) async {
    try {
      final uri = Uri.file(entity.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback using process execution
        if (Platform.isWindows) {
          await Process.run('explorer.exe', [entity.path]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [entity.path]);
        }
      }
    } catch (e) {
      debugPrint('Failed to open file: $e');
    }
  }

  Future<void> createNewFile(String name) async {
    try {
      final basePath = await _getFilesDirectoryPath();
      var fileName = name.trim().isEmpty ? '新建文件.txt' : name.trim();
      var file = File('$basePath/$fileName');

      // Handle duplicates by adding suffix
      int counter = 2;
      final nameWithoutExt = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';
      while (file.existsSync()) {
        file = File('$basePath/$nameWithoutExt ($counter)$ext');
        counter++;
      }

      await file.create();
      await _scanStoredFiles();
    } catch (e) {
      debugPrint('Failed to create new file: $e');
    }
  }

  Future<void> createNewDirectory(String name) async {
    try {
      final basePath = await _getFilesDirectoryPath();
      var dirName = name.trim().isEmpty ? '新建文件夹' : name.trim();
      var dir = Directory('$basePath/$dirName');

      // Handle duplicates by adding suffix
      int counter = 2;
      while (dir.existsSync()) {
        dir = Directory('$basePath/$dirName ($counter)');
        counter++;
      }

      await dir.create();
      await _scanStoredFiles();
    } catch (e) {
      debugPrint('Failed to create new directory: $e');
    }
  }

  Future<void> moveFileToFolder(
    FileSystemEntity source,
    Directory targetFolder,
  ) async {
    try {
      if (source.existsSync() && targetFolder.existsSync()) {
        final segments = source.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        final fileName = segments.isEmpty ? 'Unknown' : segments.last;
        final targetPath = '${targetFolder.path}/$fileName';

        // Don't move to itself or a subfolder of itself
        if (source.path == targetFolder.path ||
            targetFolder.path.startsWith('${source.path}/')) {
          return;
        }

        if (source is File) {
          await source.rename(targetPath);
        } else if (source is Directory) {
          await source.rename(targetPath);
        }
      }
    } catch (e) {
      debugPrint('Failed to move file to folder: $e');
    }
    await _scanStoredFiles();
  }

  Future<void> openFilesDirectoryInExplorer() async {
    try {
      final path = await _getFilesDirectoryPath();
      await openDirectoryPath(path);
    } catch (e) {
      debugPrint('Failed to open directory: $e');
    }
  }

  Future<void> openDirectoryPath(String path) async {
    try {
      final uri = Uri.directory(path);
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Failed to open directory $path: $e');
    }
  }

  // --- Quick Notes ---
  Future<void> _loadNotes() async {
    final notesJson = _prefs.getString('notes');
    if (notesJson != null) {
      try {
        final decoded = jsonDecode(notesJson) as List;
        notes = decoded
            .map((item) => Note.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        notes = [];
      }
    }

    // Add default note if empty
    if (notes.isEmpty) {
      final defaultNote = Note(
        id: _uuid.v4(),
        title: '我的便签',
        content: '欢迎使用快捷便签！在这里您可以随手记录任何内容，它会自动帮您保存...',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      notes.add(defaultNote);
      await _saveNotes();
    }

    // Select first note
    activeNote = notes.first;
  }

  Future<void> _saveNotes() async {
    final encoded = jsonEncode(notes.map((item) => item.toJson()).toList());
    await _prefs.setString('notes', encoded);
  }

  Future<void> createNote() async {
    await forceSaveNotesIfPending();
    final newNote = Note(
      id: _uuid.v4(),
      title: '新建便签 ${notes.length + 1}',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    notes.insert(0, newNote);
    activeNote = newNote;
    await _saveNotes();
    notifyListeners();
  }

  Future<void> deleteNote(Note note) async {
    _notesSaveTimer?.cancel();
    notes.removeWhere((n) => n.id == note.id);

    if (notes.isEmpty) {
      activeNote = null;
      await createNote(); // Create a new empty note so there's always one
    } else if (activeNote?.id == note.id) {
      activeNote = notes.first;
    }

    await _saveNotes();
    notifyListeners();
  }

  Future<void> deleteActiveNote() async {
    if (activeNote == null) return;
    await deleteNote(activeNote!);
  }

  Future<void> selectNote(Note note) async {
    await forceSaveNotesIfPending();
    activeNote = note;
    notifyListeners();
  }

  void updateActiveNoteContent(String content) {
    if (activeNote == null) return;

    // Update content and modified timestamp in memory
    final idx = notes.indexWhere((n) => n.id == activeNote!.id);
    if (idx != -1) {
      final updated = activeNote!.copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
      notes[idx] = updated;
      activeNote = updated;

      // Debounce saving to disk
      _notesSaveTimer?.cancel();
      _notesSaveTimer = Timer(const Duration(milliseconds: 800), () async {
        await _saveNotes();
      });
    }
  }

  Future<void> updateActiveNoteTitle(String title) async {
    if (activeNote == null) return;
    _notesSaveTimer?.cancel();

    final idx = notes.indexWhere((n) => n.id == activeNote!.id);
    if (idx != -1) {
      final updated = activeNote!.copyWith(
        title: title.isEmpty ? '无标题便签' : title,
        updatedAt: DateTime.now(),
      );
      notes[idx] = updated;
      activeNote = updated;

      await _saveNotes();
      notifyListeners();
    }
  }
}
