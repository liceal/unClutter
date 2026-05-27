class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isPinned;
  final String? appName;
  final String? appIconPath;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isPinned = false,
    this.appName,
    this.appIconPath,
  });

  ClipboardItem copyWith({
    String? content,
    DateTime? timestamp,
    bool? isPinned,
    String? appName,
    String? appIconPath,
  }) {
    return ClipboardItem(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isPinned: isPinned ?? this.isPinned,
      appName: appName ?? this.appName,
      appIconPath: appIconPath ?? this.appIconPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isPinned': isPinned,
      'appName': appName,
      'appIconPath': appIconPath,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isPinned: json['isPinned'] as bool? ?? false,
      appName: json['appName'] as String?,
      appIconPath: json['appIconPath'] as String?,
    );
  }
}
