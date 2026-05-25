#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon(HWND hwnd);
  void RemoveTrayIcon();
  void ShowFromTray(HWND hwnd);
  void ShowTrayMenu(HWND hwnd);
  void HandleTrayCommand(HWND hwnd, int command_id);
  void UpdateTrayPeers(const std::vector<std::string>& peers);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      tray_channel_;
  std::vector<std::string> tray_peers_;
  HWND tray_hwnd_ = nullptr;
  bool tray_icon_added_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
