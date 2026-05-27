class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isPinned;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isPinned = false,
  });

  ClipboardItem copyWith({
    String? content,
    DateTime? timestamp,
    bool? isPinned,
  }) {
    return ClipboardItem(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isPinned': isPinned,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }
}
