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
  static const _clipboardOwnerChannel = MethodChannel('app.unclutter/clipboard_owner');

  // Singleton
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final _uuid = const Uuid();
  late SharedPreferences _prefs;

  // State Variables
  AppSettings settings = AppSettings();
  List<ClipboardItem> clipboardHistory = [];
  List<File> storedFiles = [];
  List<Note> notes = [];
  Note? activeNote;

  bool isExpanded = false;
  bool isAnimating = false;
  bool isDialogOpen = false;

  String _searchClipboardQuery = '';
  String _searchNotesQuery = '';

  String _lastSystemClipText = '';
  String _lastAppCopiedText = '';
  Timer? _clipboardTimer;
  Timer? _notesSaveTimer;
  Timer? _autoCollapseTimer;

  String _trayIconPath = '';
  StreamSubscription<FileSystemEvent>? _dirWatcher;

  // Getters for filtered items
  List<ClipboardItem> get filteredClipboardHistory {
    if (_searchClipboardQuery.isEmpty) {
      // Sort: pinned first, then by timestamp descending
      return List.from(clipboardHistory)..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.timestamp.compareTo(a.timestamp);
      });
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardHistory
        .where((item) => item.content.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.timestamp.compareTo(a.timestamp);
      });
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

    // Position window
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
  Future<void> applyWindowTriggerConfiguration({bool isStartup = false}) async {
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenWidth = primaryDisplay.size.width;

    // Calculate width (pixels or percentage of screen)
    double w;
    if (settings.isWidthPercentage) {
      w = screenWidth * (settings.panelWidthPercent / 100.0);
    } else {
      w = settings.panelWidth;
    }
    final double hCollapsed = Platform.isMacOS ? 24.0 : 3.0;

    if (isStartup) {
      WindowOptions windowOptions = WindowOptions(
        size: Size(w, hCollapsed),
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        final x = (screenWidth - w) / 2;
        if (settings.triggerMode == TriggerMode.hotkeyOnly) {
          await windowManager.hide();
        } else {
          await windowManager.setBounds(Rect.fromLTWH(x, 0, w, hCollapsed));
          await windowManager.show();
        }
      });
    } else {
      if (isExpanded) {
        // When expanding or configuration changes while expanded, ensure style properties are set
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.setSkipTaskbar(true);

        final x = (screenWidth - w) / 2;
        await windowManager.setBounds(Rect.fromLTWH(x, 0, w, 350));
        await windowManager.show();
        await windowManager.focus();
      } else {
        // When collapsing, ONLY change size or hide. DO NOT call style/show/focus operations
        // because changing window style or calling show() on Windows forces window activation
        // and steals input focus from other running applications.
        if (settings.triggerMode == TriggerMode.hotkeyOnly) {
          await windowManager.hide();
        } else {
          final x = (screenWidth - w) / 2;
          await windowManager.setBounds(Rect.fromLTWH(x, 0, w, hCollapsed));
        }
      }
    }
  }

  // --- Expand / Collapse Actions ---
  Future<void> togglePanel() async {
    if (isAnimating) return;
    if (isExpanded) {
      await collapsePanel();
    } else {
      await expandPanel();
    }
  }

  Future<void> expandPanel() async {
    if (isExpanded || isAnimating) return;
    isAnimating = true;
    isExpanded = true;
    notifyListeners();

    // 1. Expand native window bounds first to allow the animation to show
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenWidth = primaryDisplay.size.width;
    
    double w;
    if (settings.isWidthPercentage) {
      w = screenWidth * (settings.panelWidthPercent / 100.0);
    } else {
      w = settings.panelWidth;
    }
    
    final x = (screenWidth - w) / 2;
    await windowManager.setBounds(Rect.fromLTWH(x, 0, w, 350));
    await windowManager.show();
    await windowManager.focus();

    // Animation starts inside the sliding panel widget
    isAnimating = false;
  }

  Future<void> forceSaveNotesIfPending() async {
    if (_notesSaveTimer?.isActive ?? false) {
      _notesSaveTimer?.cancel();
      await _saveNotes();
    }
  }

  Future<void> collapsePanel() async {
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer?.cancel();
    await forceSaveNotesIfPending();
    isAnimating = true;
    isExpanded = false;
    notifyListeners();

    // We wait for the sliding animation to complete inside the UI before resizing the native window.
    // The UI calls AppState.onCollapseAnimationFinished() to finalize this.
  }

  Future<void> onCollapseAnimationFinished() async {
    isAnimating = false;
    await applyWindowTriggerConfiguration();
    // 不主动调 blur()：
    // - 自动收起时鼠标已在其他应用，那个应用本身持有焦点，无需干预
    // - 手动收起时 Windows 会自行将焦点交给下一个窗口
    notifyListeners();
  }

  /// 取消正在进行的收起动画，重新展开面板（用于双向滚轮平滑控制）
  void cancelCollapseAndExpand() {
    if (!isExpanded) {
      isExpanded = true;
      isAnimating = false;
      notifyListeners(); // _handleStateChange 会调用 _animationController.forward()
    }
  }

  void setDialogOpen(bool open) {
    isDialogOpen = open;
    notifyListeners();
  }

  // --- Window Listeners ---
  @override
  void onWindowBlur() {
    // 焦点丢失由 collapsePanel 主动处理，此处不做额外操作
  }

  @override
  void onWindowFocus() {
    // 重新获得焦点时取消自动收起计时器（由 panel widget 的 MouseRegion 负责）
    _autoCollapseTimer?.cancel();
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
    settings = newSettings;
    await _prefs.setString('settings', jsonEncode(settings.toJson()));
    notifyListeners();

    // Reconfigure hooks & window positions
    await _setupHotkeys();
    await applyWindowTriggerConfiguration();
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
      MenuItem(key: 'toggle', label: '显示/隐藏 Unclutter'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ];
    await trayManager.setContextMenu(Menu(items: menuItems));
    await trayManager.setToolTip('Unclutter 助手');
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

              if (Platform.isWindows) {
                try {
                  final result = await _clipboardOwnerChannel.invokeMethod('getClipboardOwner');
                  if (result is Map) {
                    appName = result['name'] as String?;
                    appIconPath = result['iconPath'] as String?;
                  }
                } catch (e) {
                  debugPrint('Failed to get clipboard owner info: $e');
                }
              }

              await addClipboardItem(text, appName: appName, appIconPath: appIconPath);
            }
          }
        }
      } catch (e) {
        debugPrint('Clipboard monitoring error: $e');
      }
    });
  }

  Future<void> addClipboardItem(String content, {String? appName, String? appIconPath}) async {
    // Avoid duplicates of the exact same content in recent clipboard history list
    clipboardHistory.removeWhere(
      (item) => item.content == content && !item.isPinned,
    );

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
      // Remove oldest unpinned items
      int unpinnedIndex = clipboardHistory.lastIndexWhere(
        (item) => !item.isPinned,
      );
      if (unpinnedIndex != -1) {
        clipboardHistory.removeAt(unpinnedIndex);
      }
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
    Future.delayed(Duration.zero, _saveClipboardHistory);
  }

  void togglePinClipboardItem(String id) {
    final idx = clipboardHistory.indexWhere((item) => item.id == id);
    if (idx != -1) {
      final item = clipboardHistory[idx];
      clipboardHistory[idx] = item.copyWith(isPinned: !item.isPinned);
      Future.delayed(Duration.zero, _saveClipboardHistory);
    }
  }

  void clearClipboardHistory() {
    clipboardHistory.removeWhere((item) => !item.isPinned);
    Future.delayed(Duration.zero, _saveClipboardHistory);
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
  }

  Future<void> _saveClipboardHistory() async {
    final encoded = jsonEncode(
      clipboardHistory.map((item) => item.toJson()).toList(),
    );
    await _prefs.setString('clipboard_history', encoded);
  }

  // --- Files Storage ---
  Future<String> _getFilesDirectoryPath() async {
    // 使用用户文档目录下的明显文件夹，方便用户找到
    late String basePath;
    if (Platform.isWindows) {
      // Windows: C:\Users\<用户名>\Documents\Unclutter暂存
      basePath = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$basePath\\Documents\\Unclutter暂存';
    } else if (Platform.isMacOS) {
      basePath = Platform.environment['HOME'] ?? '';
      basePath = '$basePath/Documents/Unclutter暂存';
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

  DateTime _getFileTime(File file) {
    try {
      if (!file.existsSync()) return DateTime(0);
      final stat = file.statSync();
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
      storedFiles = dir.listSync().whereType<File>().toList()
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
        storedFiles = dir.listSync().whereType<File>().toList()
          ..sort((a, b) {
            final timeA = _getFileTime(a);
            final timeB = _getFileTime(b);
            return timeB.compareTo(timeA);
          });
        notifyListeners();
      } catch (_) {}
    });
  }

  Future<void> addDroppedFiles(List<String> filePaths) async {
    final destPath = await _getFilesDirectoryPath();
    for (var filePath in filePaths) {
      try {
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
            debugPrint('Failed to set last modified time for copied file: $e');
          }
        }
      } catch (e) {
        debugPrint('Failed to copy file: $e');
      }
    }
    await _scanStoredFiles();
  }

  Future<void> deleteFile(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete file: $e');
    }
    await _scanStoredFiles();
  }

  Future<void> openFile(File file) async {
    try {
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback using process execution
        if (Platform.isWindows) {
          await Process.run('explorer.exe', [file.path]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [file.path]);
        }
      }
    } catch (e) {
      debugPrint('Failed to open file: $e');
    }
  }

  Future<void> openFilesDirectoryInExplorer() async {
    try {
      final path = await _getFilesDirectoryPath();
      final uri = Uri.directory(path);
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Failed to open directory: $e');
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
