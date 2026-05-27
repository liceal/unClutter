import re

with open("lib/views/files_pane.dart", "r", encoding="utf-8") as f:
    code = f.read()

# Add import
code = code.replace("import 'package:desktop_drop/desktop_drop.dart';", "import 'package:desktop_drop/desktop_drop.dart';\nimport 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;")

# Replace child: Row( in _ListFileCardState
# Looking for AnimatedContainer ... child: Row(
pattern1 = re.compile(r"(AnimatedContainer\([\s\S]*?borderRadius: BorderRadius\.circular\(6\),\s*\n\s*),(\s*)child: Row\(")
code = pattern1.sub(r"\1,\2child: sdd.DragItemWidget(\n\2  dragItemProvider: (request) {\n\2    final item = sdd.DragItem();\n\2    item.add(sdd.Formats.fileUri(widget.file.uri));\n\2    return item;\n\2  },\n\2  allowedOperations: () => [sdd.DropOperation.copy],\n\2  child: Row(", code)

# Replace child: Stack( in _GridFileCardState
pattern2 = re.compile(r"(AnimatedContainer\([\s\S]*?border: Border\.all\([\s\S]*?Colors\.transparent,\s*\n\s*\),\s*\n\s*),(\s*)child: Stack\(")
code = pattern2.sub(r"\1,\2child: sdd.DragItemWidget(\n\2  dragItemProvider: (request) {\n\2    final item = sdd.DragItem();\n\2    item.add(sdd.Formats.fileUri(widget.file.uri));\n\2    return item;\n\2  },\n\2  allowedOperations: () => [sdd.DropOperation.copy],\n\2  child: Stack(", code)

# Replace child: Row( in _DetailsFileCardState
pattern3 = re.compile(r"(AnimatedContainer\([\s\S]*?border: Border\([\s\S]*?bottom: BorderSide\([\s\S]*?color: widget\.isDark \? Colors\.white10 : Colors\.black12,\s*\n\s*\),\s*\n\s*\),\s*\n\s*),(\s*)child: Row\(")
code = pattern3.sub(r"\1,\2child: sdd.DragItemWidget(\n\2  dragItemProvider: (request) {\n\2    final item = sdd.DragItem();\n\2    item.add(sdd.Formats.fileUri(widget.file.uri));\n\2    return item;\n\2  },\n\2  allowedOperations: () => [sdd.DropOperation.copy],\n\2  child: Row(", code)

# We also need to add the closing parenthesis for sdd.DragItemWidget.
# We will do this by finding the end of the children array or the end of the row/stack.
# A simpler way is to replace the closing tags.
code = code.replace("            ],\n          ),\n        ),\n      ),\n    );\n  }\n}", "            ],\n          ),\n          ),\n        ),\n      ),\n    );\n  }\n}")
code = code.replace("              ],\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}", "              ],\n            ),\n          ),\n          ),\n        ),\n      ),\n    );\n  }\n}")

with open("lib/views/files_pane.dart", "w", encoding="utf-8") as f:
    f.write(code)
