#include "flutter_window.h"

#include <shellapi.h>
#include <windowsx.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr int kTrayShowCommand = 1001;
constexpr int kTrayRefreshCommand = 1002;
constexpr int kTrayExitCommand = 1003;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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

  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "wifi_chat_share/tray",
          &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "updatePeers") {
          std::vector<std::string> peers;
          if (const auto* args =
                  std::get_if<flutter::EncodableList>(call.arguments())) {
            for (const auto& value : *args) {
              if (const auto* text = std::get_if<std::string>(&value)) {
                peers.push_back(*text);
              }
            }
          }
          UpdateTrayPeers(peers);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  tray_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kTrayMessage:
      if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        ShowFromTray(hwnd);
        return 0;
      }
      if (LOWORD(lparam) == WM_RBUTTONUP ||
          LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayMenu(hwnd);
        return 0;
      }
      break;
    case WM_COMMAND:
      HandleTrayCommand(hwnd, LOWORD(wparam));
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon(HWND hwnd) {
  if (tray_icon_added_) {
    return;
  }

  NOTIFYICONDATA data{};
  data.cbSize = sizeof(NOTIFYICONDATA);
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"Wifi Chat Share");

  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &data) == TRUE;
  if (tray_icon_added_) {
    tray_hwnd_ = hwnd;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }

  NOTIFYICONDATA data{};
  data.cbSize = sizeof(NOTIFYICONDATA);
  data.hWnd = tray_hwnd_;
  data.uID = kTrayIconId;
  Shell_NotifyIcon(NIM_DELETE, &data);
  tray_icon_added_ = false;
  tray_hwnd_ = nullptr;
}

void FlutterWindow::ShowFromTray(HWND hwnd) {
  ShowWindow(hwnd, SW_RESTORE);
  ShowWindow(hwnd, SW_SHOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  HMENU peers_menu = CreatePopupMenu();
  if (!menu || !peers_menu) {
    if (menu) {
      DestroyMenu(menu);
    }
    if (peers_menu) {
      DestroyMenu(peers_menu);
    }
    return;
  }

  AppendMenu(menu, MF_STRING, kTrayShowCommand, L"Show Wifi Chat Share");
  AppendMenu(menu, MF_STRING, kTrayRefreshCommand, L"Refresh nearby devices");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);

  if (tray_peers_.empty()) {
    AppendMenu(peers_menu, MF_STRING | MF_GRAYED, 0, L"No nearby devices");
  } else {
    for (const auto& peer : tray_peers_) {
      AppendMenu(peers_menu, MF_STRING | MF_GRAYED, 0,
                 Utf8ToWide(peer).c_str());
    }
  }
  AppendMenu(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(peers_menu),
             L"Connections");

  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayExitCommand, L"Exit");

  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_LEFTALIGN | TPM_RIGHTBUTTON, point.x, point.y, 0,
                 hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);

  DestroyMenu(menu);
}

void FlutterWindow::HandleTrayCommand(HWND hwnd, int command_id) {
  switch (command_id) {
    case kTrayShowCommand:
      ShowFromTray(hwnd);
      return;
    case kTrayRefreshCommand:
      if (tray_channel_) {
        tray_channel_->InvokeMethod("trayRefresh", nullptr);
      }
      return;
    case kTrayExitCommand:
      RemoveTrayIcon();
      DestroyWindow(hwnd);
      return;
    default:
      return;
  }
}

void FlutterWindow::UpdateTrayPeers(const std::vector<std::string>& peers) {
  tray_peers_ = peers;
}
