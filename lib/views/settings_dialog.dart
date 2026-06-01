import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';


class SettingsDialog extends StatefulWidget {
  final AppState state;

  const SettingsDialog({
    super.key,
    required this.state,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TriggerMode _triggerMode;
  late String _hotkey;
  late bool _isDarkTheme;
  late double _hoverTimeout;
  late double _panelWidth;
  late bool _isWidthPercentage;
  late double _panelWidthPercent;
  late String _themeColorName;
  late bool _closeOnBlur;
  late int _autoCollapseDelay;
  late ThemeStyle _themeStyle;
  late double _backdropOpacity;

  final List<String> _hotkeyPresets = [
    'alt+u',
    'alt+space',
    'ctrl+alt+u',
    'ctrl+shift+u',
    'alt+n',
  ];

  String _dataDir = '加载中...';
  String _filesDir = '加载中...';
  late TextEditingController _customFilesPathController;

  @override
  void initState() {
    super.initState();
    _triggerMode = widget.state.settings.triggerMode;
    _hotkey = widget.state.settings.hotkey;
    _isDarkTheme = widget.state.settings.isDarkTheme;
    _hoverTimeout = widget.state.settings.hoverTimeoutMs.toDouble();
    _panelWidth = widget.state.settings.panelWidth;
    _isWidthPercentage = widget.state.settings.isWidthPercentage;
    _panelWidthPercent = widget.state.settings.panelWidthPercent;
    _themeColorName = (widget.state.settings.themeColorName as dynamic) ?? 'blue';
    _closeOnBlur = widget.state.settings.closeOnBlur;
    _autoCollapseDelay = widget.state.settings.autoCollapseDelay;
    _themeStyle = widget.state.settings.themeStyle;
    _backdropOpacity = widget.state.settings.backdropOpacity;
    _customFilesPathController = TextEditingController(text: widget.state.settings.customFilesPath ?? '');

    // Fetch storage directories
    getApplicationSupportDirectory().then((dir) {
      if (mounted) {
        setState(() {
          _dataDir = dir.path;
        });
      }
    });
    widget.state.getFilesDirectoryPath().then((path) {
      if (mounted) {
        setState(() {
          _filesDir = path;
        });
      }
    });
  }

  @override
  void dispose() {
    _customFilesPathController.dispose();
    super.dispose();
  }

  void _save() {
    final updated = AppSettings(
      triggerMode: _triggerMode,
      hotkey: _hotkey,
      isDarkTheme: _isDarkTheme,
      hoverTimeoutMs: _hoverTimeout.toInt(),
      panelWidth: _panelWidth,
      isWidthPercentage: _isWidthPercentage,
      panelWidthPercent: _panelWidthPercent,
      themeColorName: _themeColorName,
      closeOnBlur: _closeOnBlur,
      autoCollapseDelay: _autoCollapseDelay,
      customFilesPath: _customFilesPathController.text.trim().isEmpty
          ? null
          : _customFilesPathController.text.trim(),
      themeStyle: _themeStyle,
      backdropOpacity: _backdropOpacity,
    );
    widget.state.updateSettings(updated);
    Navigator.of(context).pop();
  }


  String _getTriggerModeLabel(TriggerMode mode) {
    switch (mode) {
      case TriggerMode.both:
        return '混合模式 (快捷键、边缘悬停与滚轮)';
      case TriggerMode.hotkeyOnly:
        return '仅全局快捷键';
      case TriggerMode.hoverOnly:
        return '仅屏幕边缘悬停';
      case TriggerMode.scrollOnly:
        return '仅鼠标滚轮下滑';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _isDarkTheme ? Colors.white : Colors.black87;
    final subColor = _isDarkTheme ? Colors.white60 : Colors.black54;
    final dialogBg = _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final dropdownBg = _isDarkTheme ? const Color(0xFF2C2C2C) : Colors.grey[100];
    final accentColor = AppTheme.getAccentColor(_themeColorName, _isDarkTheme);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isDarkTheme ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Pod 设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const Divider(height: 20),
            
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trigger Mode Option
                    Text(
                      '唤醒方式',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<TriggerMode>(
                      value: _triggerMode,
                      dropdownColor: dropdownBg,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _isDarkTheme ? Colors.white24 : Colors.black12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentColor),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: TriggerMode.values.map((mode) {
                        return DropdownMenuItem<TriggerMode>(
                          value: mode,
                          child: Text(
                            _getTriggerModeLabel(mode),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _triggerMode = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Hotkey Configuration
                    if (_triggerMode != TriggerMode.hoverOnly && _triggerMode != TriggerMode.scrollOnly) ...[
                      Text(
                        '全局快捷键',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '可在任意界面快速呼出/收起面板。选择下方下拉框可更改快捷键：',
                        style: TextStyle(
                          fontSize: 11,
                          color: subColor.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _hotkeyPresets.contains(_hotkey) ? _hotkey : _hotkeyPresets.first,
                        dropdownColor: dropdownBg,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: _isDarkTheme ? Colors.white24 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: accentColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: _hotkeyPresets.map((key) {
                          return DropdownMenuItem<String>(
                            value: key,
                            child: Text(
                              key.toUpperCase().replaceAll('+', ' + '),
                              style: TextStyle(fontSize: 13, color: textColor),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _hotkey = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Hover Timeout config
                    if (_triggerMode != TriggerMode.hotkeyOnly && _triggerMode != TriggerMode.scrollOnly) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '边缘悬停延迟',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: subColor,
                            ),
                          ),
                          Text(
                            '${_hoverTimeout.toInt()} 毫秒',
                            style: TextStyle(fontSize: 12, color: textColor),
                          ),
                        ],
                      ),
                      Slider(
                        value: _hoverTimeout,
                        min: 100,
                        max: 1000,
                        divisions: 9,
                        activeColor: accentColor,
                        inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                        label: '${_hoverTimeout.toInt()}ms',
                        onChanged: (val) {
                          setState(() {
                            _hoverTimeout = val;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Panel Width config
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '面板宽度',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: _isDarkTheme
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isWidthPercentage = false;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: !_isWidthPercentage
                                        ? accentColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '固定像素',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: !_isWidthPercentage
                                          ? Colors.white
                                          : textColor.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isWidthPercentage = true;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _isWidthPercentage
                                        ? accentColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '屏幕百分比',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _isWidthPercentage
                                          ? Colors.white
                                          : textColor.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!_isWidthPercentage) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${_panelWidth.toInt()} px',
                            style: TextStyle(fontSize: 11, color: textColor),
                          ),
                        ],
                      ),
                      Slider(
                        value: _panelWidth,
                        min: 400,
                        max: 1600,
                        divisions: 24,
                        activeColor: accentColor,
                        inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                        label: '${_panelWidth.toInt()}px',
                        onChanged: (val) {
                          setState(() {
                            _panelWidth = val;
                          });
                        },
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${_panelWidthPercent.toInt()}%',
                            style: TextStyle(fontSize: 11, color: textColor),
                          ),
                        ],
                      ),
                      Slider(
                        value: _panelWidthPercent,
                        min: 30,
                        max: 100,
                        divisions: 70,
                        activeColor: accentColor,
                        inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                        label: '${_panelWidthPercent.toInt()}%',
                        onChanged: (val) {
                          setState(() {
                            _panelWidthPercent = val;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Backdrop opacity
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '背板透明度',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        Text(
                          '${(_backdropOpacity * 100).round()}%',
                          style: TextStyle(fontSize: 12, color: textColor),
                        ),
                      ],
                    ),
                    Slider(
                      value: _backdropOpacity,
                      min: 0.35,
                      max: 1.0,
                      divisions: 65,
                      activeColor: accentColor,
                      inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                      label: '${(_backdropOpacity * 100).round()}%',
                      onChanged: (val) {
                        setState(() {
                          _backdropOpacity = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // Theme Accent Selection
                    Text(
                      '主题颜色',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['blue', 'orange', 'green', 'purple', 'red'].map((colorName) {
                        final color = AppTheme.getAccentColor(colorName, _isDarkTheme);
                        final isSelected = _themeColorName == colorName;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _themeColorName = colorName;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected 
                                    ? (_isDarkTheme ? Colors.white : Colors.black87) 
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: color.withOpacity(0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ] : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Switches: Dark Theme & Close on Blur
                    // Auto-collapse after mouse exits
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '鼠标离开后自动收起',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: subColor,
                              ),
                            ),
                            Text(
                              _autoCollapseDelay == 0
                                  ? '已禁用'
                                  : '$_autoCollapseDelay 秒后收起',
                              style: TextStyle(fontSize: 11, color: subColor.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: _autoCollapseDelay.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      activeColor: accentColor,
                      inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                      label: _autoCollapseDelay == 0 ? '禁用' : '$_autoCollapseDelay 秒',
                      onChanged: (val) {
                        setState(() {
                          _autoCollapseDelay = val.toInt();
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // Switches: Dark Theme
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '深色主题',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        Switch(
                          value: _isDarkTheme,
                          activeColor: accentColor,
                          onChanged: (val) {
                            setState(() {
                              _isDarkTheme = val;
                            });
                          },
                        ),
                      ],
                    ),
                    // closeOnBlur 已永久禁用，改为鼠标滚轮上滑收起
                    const SizedBox(height: 12),

                    const Divider(height: 24),
                    Text(
                      '存储位置',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 1. 便签与剪贴板数据
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '数据目录 (便签与剪贴板)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                widget.state.openDirectoryPath(_dataDir);
                              },
                              icon: Icon(Icons.folder_open, size: 14, color: accentColor),
                              label: Text('打开目录', style: TextStyle(fontSize: 11, color: accentColor)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _dataDir,
                          style: TextStyle(
                            fontSize: 11,
                            color: subColor.withOpacity(0.8),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. 暂存文件目录
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '文件目录 (暂存文件)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                            Row(
                              children: [
                                if (_customFilesPathController.text.trim().isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _customFilesPathController.clear();
                                        widget.state.getFilesDirectoryPath().then((path) {
                                          if (mounted) {
                                            setState(() {
                                              _filesDir = path;
                                            });
                                          }
                                        });
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('恢复默认', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                  ),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  onPressed: () {
                                    widget.state.openDirectoryPath(_filesDir);
                                  },
                                  icon: Icon(Icons.folder_open, size: 14, color: accentColor),
                                  label: Text('打开目录', style: TextStyle(fontSize: 11, color: accentColor)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _customFilesPathController,
                          style: TextStyle(fontSize: 12, color: textColor, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            hintText: '默认: 用户文档目录/Pod暂存',
                            hintStyle: TextStyle(fontSize: 12, color: subColor.withOpacity(0.5)),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: _isDarkTheme ? Colors.white24 : Colors.black12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: accentColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            if (val.trim().isEmpty) {
                              widget.state.getFilesDirectoryPath().then((path) {
                                if (mounted) {
                                  setState(() {
                                    _filesDir = path;
                                  });
                                }
                              });
                            } else {
                              setState(() {
                                _filesDir = val.trim();
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '当前实际路径: $_filesDir',
                          style: TextStyle(
                            fontSize: 10,
                            color: subColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Dialog Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  child: Text(
                    '取消',
                    style: TextStyle(color: subColor),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
