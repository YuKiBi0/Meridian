#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellscalingapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Arg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  return it == args.end() ? nullptr : &it->second;
}

int ArgInt(const EncodableMap& args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (!v) return 0;
  if (auto i = std::get_if<int32_t>(v)) return *i;
  if (auto l = std::get_if<int64_t>(v)) return static_cast<int>(*l);
  if (auto d = std::get_if<double>(v)) return static_cast<int>(*d);
  return 0;
}

double ArgDouble(const EncodableMap& args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (!v) return 0;
  if (auto d = std::get_if<double>(v)) return *d;
  if (auto i = std::get_if<int32_t>(v)) return *i;
  if (auto l = std::get_if<int64_t>(v)) return static_cast<double>(*l);
  return 0;
}

bool ArgBool(const EncodableMap& args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  auto b = v ? std::get_if<bool>(v) : nullptr;
  return b && *b;
}

EncodableMap RectMap(const RECT& r) {
  return EncodableMap{
      {EncodableValue("x"), EncodableValue(static_cast<int>(r.left))},
      {EncodableValue("y"), EncodableValue(static_cast<int>(r.top))},
      {EncodableValue("w"), EncodableValue(static_cast<int>(r.right - r.left))},
      {EncodableValue("h"), EncodableValue(static_cast<int>(r.bottom - r.top))},
  };
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto list = reinterpret_cast<EncodableList*>(data);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return TRUE;
  UINT dpi_x = 96, dpi_y = 96;
  if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    dpi_x = 96;
  }
  list->push_back(EncodableValue(EncodableMap{
      {EncodableValue("id"), EncodableValue(Utf8FromUtf16(info.szDevice))},
      {EncodableValue("primary"),
       EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0)},
      {EncodableValue("scale"), EncodableValue(dpi_x / 96.0)},
      {EncodableValue("monitor"), EncodableValue(RectMap(info.rcMonitor))},
      {EncodableValue("work"), EncodableValue(RectMap(info.rcWork))},
  }));
  return TRUE;
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

  window_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "meridian/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleWindowCall(call, std::move(result));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::UpdateLayered() {
  HWND hwnd = GetHandle();
  LONG ex = GetWindowLong(hwnd, GWL_EXSTYLE);
  bool layered = click_through_ || opacity_ < 1.0;
  if (layered) {
    ex |= WS_EX_LAYERED;
  } else {
    ex &= ~WS_EX_LAYERED;
  }
  if (click_through_) {
    ex |= WS_EX_TRANSPARENT;
  } else {
    ex &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLong(hwnd, GWL_EXSTYLE, ex);
  if (layered) {
    SetLayeredWindowAttributes(hwnd, 0, static_cast<BYTE>(opacity_ * 255),
                               LWA_ALPHA);
  }
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HWND hwnd = GetHandle();
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const EncodableMap empty;
  const EncodableMap& a = args ? *args : empty;
  const std::string& method = call.method_name();

  if (method == "monitors") {
    EncodableList list;
    EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                        reinterpret_cast<LPARAM>(&list));
    result->Success(EncodableValue(list));
  } else if (method == "setBounds") {
    // Physical pixels. Never activates and never changes the z-order.
    RECT r{ArgInt(a, "x"), ArgInt(a, "y"), ArgInt(a, "x") + ArgInt(a, "w"),
           ArgInt(a, "y") + ArgInt(a, "h")};
    last_bounds_ = r;
    has_bounds_ = true;
    // Optional visible region (window-relative physical rects). Outside it
    // the window neither paints nor takes clicks, so a view and a distant
    // reminder card can share one window without blocking what is between.
    // Only touched when a region is wanted or has to be removed, and before
    // the move, so plain resizes behave exactly as without regions.
    const EncodableValue* rv = Arg(a, "region");
    const auto* rects = rv ? std::get_if<EncodableList>(rv) : nullptr;
    if (rects || has_region_) {
      HRGN region = nullptr;
      if (rects) {
        region = CreateRectRgn(0, 0, 0, 0);
        for (const auto& v : *rects) {
          const auto* m = std::get_if<EncodableMap>(&v);
          if (!m) continue;
          HRGN part = CreateRectRgn(ArgInt(*m, "x"), ArgInt(*m, "y"),
                                    ArgInt(*m, "x") + ArgInt(*m, "w"),
                                    ArgInt(*m, "y") + ArgInt(*m, "h"));
          CombineRgn(region, region, part, RGN_OR);
          DeleteObject(part);
        }
      }
      // The system owns the region after this call.
      SetWindowRgn(hwnd, region, FALSE);
      has_region_ = region != nullptr;
    }
    SetWindowPos(hwnd, nullptr, r.left, r.top, r.right - r.left,
                 r.bottom - r.top,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    if (rects) {
      RedrawWindow(hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN);
    }
    result->Success();
  } else if (method == "setTopmost") {
    // Re-asserting HWND_TOPMOST lifts the window above other topmost
    // windows (e.g. a slideshow) without taking focus.
    SetWindowPos(hwnd, ArgBool(a, "on") ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0,
                 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    result->Success();
  } else if (method == "setClickThrough") {
    click_through_ = ArgBool(a, "on");
    UpdateLayered();
    result->Success();
  } else if (method == "setOpacity") {
    opacity_ = ArgDouble(a, "value");
    if (opacity_ < 0.1) opacity_ = 0.1;
    if (opacity_ > 1.0) opacity_ = 1.0;
    UpdateLayered();
    result->Success();
  } else if (method == "setNoActivate") {
    LONG ex = GetWindowLong(hwnd, GWL_EXSTYLE);
    ex = ArgBool(a, "on") ? (ex | WS_EX_NOACTIVATE) : (ex & ~WS_EX_NOACTIVATE);
    SetWindowLong(hwnd, GWL_EXSTYLE, ex);
    result->Success();
  } else if (method == "bounds") {
    RECT r{};
    GetWindowRect(hwnd, &r);
    result->Success(EncodableValue(RectMap(r)));
  } else if (method == "contentBounds") {
    // The Flutter view's own window, for checking it follows the frame.
    RECT r{};
    HWND view = flutter_controller_->view()->GetNativeWindow();
    GetClientRect(view, &r);
    result->Success(EncodableValue(RectMap(r)));
  } else if (method == "scale") {
    result->Success(EncodableValue(GetDpiForWindow(hwnd) / 96.0));
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Windows keeps captioned windows at least ~136x39 px; a 4 px bar must be
  // able to be 4 px. Handled before plugins, which would keep the default.
  if (message == WM_GETMINMAXINFO) {
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize = POINT{1, 1};
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
    case WM_DPICHANGED:
      // Moving to a monitor with another scale: keep the bounds we chose
      // instead of the system's suggestion; Dart re-lays out afterwards.
      if (has_bounds_) {
        SetWindowPos(hwnd, nullptr, last_bounds_.left, last_bounds_.top,
                     last_bounds_.right - last_bounds_.left,
                     last_bounds_.bottom - last_bounds_.top,
                     SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
