#include "flutter_window.h"

#include <optional>
#include <psapi.h>
#include <shellapi.h>
#include <cwctype>
#include <string>
#include <chrono>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

#pragma comment(lib, "gdiplus.lib")

FlutterWindow* FlutterWindow::scroll_hook_window_ = nullptr;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Force window to be borderless popup style from the beginning
  HWND hwnd = GetHandle();
  LONG style = GetWindowLong(hwnd, GWL_STYLE);
  style &= ~WS_CAPTION;
  style &= ~WS_THICKFRAME;
  style &= ~WS_SYSMENU;
  style |= WS_POPUP;
  SetWindowLong(hwnd, GWL_STYLE, style);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

  // Initialize GDI+
  Gdiplus::GdiplusStartupInput gdiplusStartupInput;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplusStartupInput, NULL);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Register Method Channel
  method_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(),
      "app.pod/clipboard_owner",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<>& call,
         std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "getClipboardOwner") {
          HWND hwnd = GetClipboardOwner();
          if (!hwnd) {
            hwnd = GetForegroundWindow();
          }

          if (!hwnd) {
            result->Success(flutter::EncodableValue(flutter::EncodableMap{}));
            return;
          }

          DWORD process_id = 0;
          GetWindowThreadProcessId(hwnd, &process_id);

          HANDLE process_handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
          wchar_t process_path[MAX_PATH] = {0};
          DWORD path_size = MAX_PATH;
          if (process_handle) {
            QueryFullProcessImageNameW(process_handle, 0, process_path, &path_size);
            CloseHandle(process_handle);
          }

          std::wstring path_ws(process_path);
          if (path_ws.empty()) {
            result->Success(flutter::EncodableValue(flutter::EncodableMap{}));
            return;
          }

          // Extract executable name (e.g. C:\Windows\System32\notepad.exe -> notepad)
          size_t last_slash = path_ws.find_last_of(L"\\/");
          std::wstring exe_name = (last_slash == std::wstring::npos) ? path_ws : path_ws.substr(last_slash + 1);
          size_t dot = exe_name.find_last_of(L".");
          if (dot != std::wstring::npos) {
            exe_name = exe_name.substr(0, dot);
          }

          // Capitalize first letter for display
          std::wstring display_name = exe_name;
          if (!display_name.empty()) {
            display_name[0] = towupper(display_name[0]);
          }

          // Get temp directory and icon directory
          wchar_t temp_path[MAX_PATH];
          GetTempPathW(MAX_PATH, temp_path);
          std::wstring icon_dir = std::wstring(temp_path) + L"pod_icons";
          CreateDirectoryW(icon_dir.c_str(), NULL);

          std::wstring dest_file = icon_dir + L"\\" + exe_name + L".png";
          bool icon_saved = false;

          // Check if file exists
          DWORD attrib = GetFileAttributesW(dest_file.c_str());
          if (attrib != INVALID_FILE_ATTRIBUTES && !(attrib & FILE_ATTRIBUTE_DIRECTORY)) {
            icon_saved = true;
          } else {
            // Extract and save icon
            SHFILEINFOW sfi = {0};
            SHGetFileInfoW(process_path, 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON);
            HICON hIcon = sfi.hIcon;
            if (hIcon) {
              Gdiplus::Bitmap bitmap(hIcon);
              CLSID pngClsid;
              UINT num = 0, size = 0;
              Gdiplus::GetImageEncodersSize(&num, &size);
              if (size > 0) {
                Gdiplus::ImageCodecInfo* pImageCodecInfo = (Gdiplus::ImageCodecInfo*)(malloc(size));
                if (pImageCodecInfo != NULL) {
                  Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);
                  for (UINT j = 0; j < num; ++j) {
                    if (wcscmp(pImageCodecInfo[j].MimeType, L"image/png") == 0) {
                      pngClsid = pImageCodecInfo[j].Clsid;
                      Gdiplus::Status status = bitmap.Save(dest_file.c_str(), &pngClsid, NULL);
                      if (status == Gdiplus::Ok) {
                        icon_saved = true;
                      }
                      break;
                    }
                  }
                  free(pImageCodecInfo);
                }
              }
              DestroyIcon(hIcon);
            }
          }

          // Convert display_name and dest_file to UTF-8 strings
          std::string name_utf8;
          int size_needed = WideCharToMultiByte(CP_UTF8, 0, display_name.c_str(), -1, NULL, 0, NULL, NULL);
          if (size_needed > 0) {
            name_utf8.resize(size_needed - 1);
            WideCharToMultiByte(CP_UTF8, 0, display_name.c_str(), -1, &name_utf8[0], size_needed, NULL, NULL);
          }

          std::string path_utf8;
          if (icon_saved) {
            int size_needed_path = WideCharToMultiByte(CP_UTF8, 0, dest_file.c_str(), -1, NULL, 0, NULL, NULL);
            if (size_needed_path > 0) {
              path_utf8.resize(size_needed_path - 1);
              WideCharToMultiByte(CP_UTF8, 0, dest_file.c_str(), -1, &path_utf8[0], size_needed_path, NULL, NULL);
            }
          }

          flutter::EncodableMap response;
          response[flutter::EncodableValue("name")] = flutter::EncodableValue(name_utf8);
          if (icon_saved) {
            response[flutter::EncodableValue("iconPath")] = flutter::EncodableValue(path_utf8);
          } else {
            response[flutter::EncodableValue("iconPath")] = flutter::EncodableValue("");
          }

          result->Success(flutter::EncodableValue(response));
        } else {
          result->NotImplemented();
        }
      });

  // Register focus management Method Channel
  focus_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(),
      "app.pod/focus_manager",
      &flutter::StandardMethodCodec::GetInstance());

  focus_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "savePreviousApp") {
          HWND fg = GetForegroundWindow();
          if (fg && fg != GetHandle()) {
            previous_hwnd_ = fg;
          }
          result->Success();
        } else if (call.method_name() == "restorePreviousApp") {
          if (previous_hwnd_ && IsWindow(previous_hwnd_)) {
            SetForegroundWindow(previous_hwnd_);
          }
          previous_hwnd_ = nullptr;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  menu_bar_scroll_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(),
      "app.pod/menu_bar_scroll",
      &flutter::StandardMethodCodec::GetInstance());

  InstallMouseHook();

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveMouseHook();

  if (method_channel_) {
    method_channel_ = nullptr;
  }
  if (focus_channel_) {
    focus_channel_ = nullptr;
  }
  if (menu_bar_scroll_channel_) {
    menu_bar_scroll_channel_ = nullptr;
  }

  // Shutdown GDI+
  Gdiplus::GdiplusShutdown(gdiplus_token_);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::InstallMouseHook() {
  if (mouse_hook_ != nullptr) {
    return;
  }
  scroll_hook_window_ = this;
  mouse_hook_ =
      SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc, GetModuleHandle(nullptr), 0);
}

void FlutterWindow::RemoveMouseHook() {
  if (mouse_hook_ != nullptr) {
    UnhookWindowsHookEx(mouse_hook_);
    mouse_hook_ = nullptr;
  }
  if (scroll_hook_window_ == this) {
    scroll_hook_window_ = nullptr;
  }
}

LRESULT CALLBACK FlutterWindow::LowLevelMouseProc(int n_code, WPARAM wparam,
                                                  LPARAM lparam) {
  if (n_code == HC_ACTION && wparam == WM_MOUSEWHEEL && scroll_hook_window_) {
    const auto* mouse = reinterpret_cast<MSLLHOOKSTRUCT*>(lparam);
    const int wheel_delta = GET_WHEEL_DELTA_WPARAM(mouse->mouseData);
    scroll_hook_window_->HandleGlobalMouseWheel(mouse->pt, wheel_delta);
  }
  return CallNextHookEx(nullptr, n_code, wparam, lparam);
}

bool FlutterWindow::TryGetTopEdgeMonitorInfo(
    POINT point,
    flutter::EncodableMap* screen_info) {
  HMONITOR monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONULL);
  if (!monitor) {
    return false;
  }

  MONITORINFO monitor_info;
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  const RECT& frame = monitor_info.rcMonitor;
  constexpr LONG kTopEdgeHeight = 20;
  const bool is_on_top_edge =
      point.x >= frame.left && point.x < frame.right &&
      point.y >= frame.top && point.y <= frame.top + kTopEdgeHeight;
  if (!is_on_top_edge) {
    return false;
  }

  const RECT& work = monitor_info.rcWork;
  (*screen_info)[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(frame.left));
  (*screen_info)[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(frame.top));
  (*screen_info)[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<double>(frame.right - frame.left));
  (*screen_info)[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<double>(frame.bottom - frame.top));
  (*screen_info)[flutter::EncodableValue("visibleY")] =
      flutter::EncodableValue(static_cast<double>(work.top));
  (*screen_info)[flutter::EncodableValue("visibleHeight")] =
      flutter::EncodableValue(static_cast<double>(work.bottom - work.top));
  return true;
}

void FlutterWindow::HandleGlobalMouseWheel(POINT point, int wheel_delta) {
  if (!menu_bar_scroll_channel_ || wheel_delta == 0) {
    return;
  }

  flutter::EncodableMap args;
  if (!TryGetTopEdgeMonitorInfo(point, &args)) {
    return;
  }

  // Windows reports negative wheel deltas for a downward scroll. Dart uses
  // positive dy to expand and negative dy to collapse, matching Flutter's
  // PointerScrollEvent.scrollDelta.dy convention.
  const double dy = wheel_delta < 0 ? 1.0 : -1.0;
  if (dy > 0) {
    const auto now = std::chrono::steady_clock::now();
    if (last_scroll_time_ != std::chrono::steady_clock::time_point::min() &&
        now - last_scroll_time_ < std::chrono::milliseconds(200)) {
      return;
    }
    last_scroll_time_ = now;
  }

  args[flutter::EncodableValue("dy")] = flutter::EncodableValue(dy);
  menu_bar_scroll_channel_->InvokeMethod(
      "onMenuBarScroll",
      std::make_unique<flutter::EncodableValue>(args));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Prevent caption/thickframe/sysmenu styles from being added back
  if (message == WM_STYLECHANGING) {
    STYLESTRUCT* ss = reinterpret_cast<STYLESTRUCT*>(lparam);
    if (wparam == GWL_STYLE) {
      ss->styleNew &= ~WS_CAPTION;
      ss->styleNew &= ~WS_THICKFRAME;
      ss->styleNew &= ~WS_SYSMENU;
      ss->styleNew |= WS_POPUP;
    }
  }

  // Overwrite min/max constraints to allow window height to be less than 39px
  if (message == WM_GETMINMAXINFO) {
    if (flutter_controller_) {
      flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    }
    MINMAXINFO* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
    mmi->ptMinTrackSize.x = 0;
    mmi->ptMinTrackSize.y = 0;
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
