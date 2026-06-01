enum TriggerMode {
  both,
  hotkeyOnly,
  hoverOnly,
  scrollOnly,
}

enum ThemeStyle {
  normal,
  compact,
}

class AppSettings {
  final TriggerMode triggerMode;
  final String hotkey; // e.g., "alt+u"
  final bool isDarkTheme;
  final int hoverTimeoutMs; // Delay before hover triggers slide-down
  final double panelWidth;
  final bool isWidthPercentage;
  final double panelWidthPercent;
  final String? _themeColorName;
  final bool? _closeOnBlur;
  /// Seconds to wait after mouse leaves before auto-collapsing. 0 = disabled.
  final int autoCollapseDelay;
  final String? customFilesPath;
  final ThemeStyle themeStyle;
  final double backdropOpacity;

  String get themeColorName => _themeColorName ?? 'blue';
  bool get closeOnBlur => _closeOnBlur ?? false;

  AppSettings({
    this.triggerMode = TriggerMode.both,
    this.hotkey = 'alt+u',
    this.isDarkTheme = true,
    this.hoverTimeoutMs = 300,
    this.panelWidth = 900.0,
    this.isWidthPercentage = true,
    this.panelWidthPercent = 100.0,
    String? themeColorName = 'blue',
    bool? closeOnBlur = false,
    this.autoCollapseDelay = 3,
    this.customFilesPath,
    this.themeStyle = ThemeStyle.compact,
    this.backdropOpacity = 0.92,
  })  : _themeColorName = themeColorName,
        _closeOnBlur = closeOnBlur;

  AppSettings copyWith({
    TriggerMode? triggerMode,
    String? hotkey,
    bool? isDarkTheme,
    int? hoverTimeoutMs,
    double? panelWidth,
    bool? isWidthPercentage,
    double? panelWidthPercent,
    String? themeColorName,
    bool? closeOnBlur,
    int? autoCollapseDelay,
    String? customFilesPath,
    ThemeStyle? themeStyle,
    double? backdropOpacity,
  }) {
    return AppSettings(
      triggerMode: triggerMode ?? this.triggerMode,
      hotkey: hotkey ?? this.hotkey,
      isDarkTheme: isDarkTheme ?? this.isDarkTheme,
      hoverTimeoutMs: hoverTimeoutMs ?? this.hoverTimeoutMs,
      panelWidth: panelWidth ?? this.panelWidth,
      isWidthPercentage: isWidthPercentage ?? this.isWidthPercentage,
      panelWidthPercent: panelWidthPercent ?? this.panelWidthPercent,
      themeColorName: themeColorName ?? this.themeColorName,
      closeOnBlur: closeOnBlur ?? this.closeOnBlur,
      autoCollapseDelay: autoCollapseDelay ?? this.autoCollapseDelay,
      customFilesPath: customFilesPath ?? this.customFilesPath,
      themeStyle: themeStyle ?? this.themeStyle,
      backdropOpacity: backdropOpacity ?? this.backdropOpacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'triggerMode': triggerMode.name,
      'hotkey': hotkey,
      'isDarkTheme': isDarkTheme,
      'hoverTimeoutMs': hoverTimeoutMs,
      'panelWidth': panelWidth,
      'isWidthPercentage': isWidthPercentage,
      'panelWidthPercent': panelWidthPercent,
      'themeColorName': themeColorName,
      'closeOnBlur': closeOnBlur,
      'autoCollapseDelay': autoCollapseDelay,
      'customFilesPath': customFilesPath,
      'themeStyle': themeStyle.name,
      'backdropOpacity': backdropOpacity,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    TriggerMode parseTriggerMode(String? name) {
      if (name == null) return TriggerMode.both;
      return TriggerMode.values.firstWhere(
        (e) => e.name == name,
        orElse: () => TriggerMode.both,
      );
    }

    ThemeStyle parseThemeStyle(String? name) {
      return ThemeStyle.compact;
    }

    return AppSettings(
      triggerMode: parseTriggerMode(json['triggerMode'] as String?),
      hotkey: json['hotkey'] as String? ?? 'alt+u',
      isDarkTheme: json['isDarkTheme'] as bool? ?? true,
      hoverTimeoutMs: json['hoverTimeoutMs'] as int? ?? 300,
      panelWidth: (json['panelWidth'] as num?)?.toDouble() ?? 900.0,
      isWidthPercentage: json['isWidthPercentage'] as bool? ?? true,
      panelWidthPercent: (json['panelWidthPercent'] as num?)?.toDouble() ?? 100.0,
      themeColorName: json['themeColorName'] as String?,
      closeOnBlur: json['closeOnBlur'] as bool? ?? false,
      autoCollapseDelay: json['autoCollapseDelay'] as int? ?? 3,
      customFilesPath: json['customFilesPath'] as String?,
      themeStyle: parseThemeStyle(json['themeStyle'] as String?),
      backdropOpacity: (json['backdropOpacity'] as num?)?.toDouble() ?? 0.92,
    );
  }

}
