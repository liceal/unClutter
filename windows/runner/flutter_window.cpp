#include "flutter_window.h"

#include <optional>
#include <psapi.h>
#include <shellapi.h>
#include <cwctype>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

#pragma comment(lib, "gdiplus.lib")

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

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (method_channel_) {
    method_channel_ = nullptr;
  }
  if (focus_channel_) {
    focus_channel_ = nullptr;
  }

  // Shutdown GDI+
  Gdiplus::GdiplusShutdown(gdiplus_token_);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
