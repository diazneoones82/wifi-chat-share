# Wifi Chat Share

Wifi Chat Share is a cross-platform LAN chat and file sharing app built with Flutter. It lets Windows PCs, Macs, Linux desktops, Android phones, and iPhones find each other on the same Wi-Fi network, then exchange messages and any file type directly between devices.

No cloud server is used. Every device that should appear in the list must have Wifi Chat Share open on the same Wi-Fi/LAN.

## Features

- Nearby device discovery over local Wi-Fi/LAN
- One-to-one chat
- Share pictures, videos, documents, archives, installers, and any other file format
- Received-file save location selector on desktop
- Default received-file location under Documents/app storage when no folder is selected
- Light and dark mode toggle
- Optional notifications for incoming chat messages and received files
- Refresh button that removes closed/stale peer entries without restarting the app
- Shared Flutter codebase for Windows, Android, iOS, macOS, and Linux

## Network Ports

Allow these ports on every desktop firewall that will receive chats or files:

| Purpose | Protocol | Port |
| --- | --- | --- |
| Device discovery | UDP | `45872` |
| Chat and file transfer | TCP | `45873` |

If one device can see or send to another but replies fail, the receiving device is usually blocking TCP `45873`.

## Using The App

1. Connect all devices to the same Wi-Fi network.
2. Open Wifi Chat Share on every device.
3. Allow local network, firewall, and notification prompts when asked.
4. Wait a few seconds for devices to appear.
5. Select a nearby device.
6. Type a message or choose a file to send.
7. Use Refresh to remove devices that have closed the app or left the network.

The app can only discover devices that are also running Wifi Chat Share. Operating systems do not allow an app to silently list every phone or computer on a network.

The top status bar shows **Ping IP** for the current device. Use that address from another PC or phone when testing basic network reachability with `ping`.

## Windows App

### Run The Portable Build

Use the full release folder or ZIP. Do not copy only `wifi_chat_share.exe`; Flutter desktop apps need the DLLs and `data` folder next to the executable.

Current local Windows output:

```text
build/windows/x64/runner/Release/wifi_chat_share.exe
```

Portable ZIP output:

```text
dist/WifiChatShare-Windows-x64-portable.zip
```

To run on a new Windows desktop:

1. Copy `WifiChatShare-Windows-x64-portable.zip` to the computer.
2. Right-click the ZIP and choose Extract All.
3. Open the extracted folder.
4. Run the firewall script as Administrator.
5. Start `wifi_chat_share.exe`.

### Run The Firewall Script As Administrator

On every Windows PC:

1. Open the extracted app folder.
2. Right-click `Allow_WifiChatShare_Firewall.ps1`.
3. Choose Run with PowerShell.
4. Approve the Administrator/UAC prompt.

If Windows blocks script execution, open PowerShell as Administrator in the extracted folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Allow_WifiChatShare_Firewall.ps1
```

The script allows inbound UDP `45872` and TCP `45873`.

### Windows Settings

Open the gear icon in the app:

- Dark mode: switches the app theme.
- Notifications: enables popup notifications for received messages and files.
- Start with Windows: opens Wifi Chat Share automatically when the current Windows user signs in.
- Received files location: choose the download/save folder.
- The Settings screen uses the shared compact scrollable layout, so the same cleaner Settings design appears on Windows, Android, iOS, macOS, and Linux after each platform is rebuilt.

If no folder is selected, received files are saved in the app's default Documents location.

### Windows Taskbar Tray

The Windows app keeps running when minimized and moves to the taskbar tray/notification area.

- Click Minimize to hide the app window while discovery, chat, and file receiving continue.
- Double-click the tray icon to show the app again.
- Right-click the tray icon for:
  - Show Wifi Chat Share
  - Refresh nearby devices
  - Connections list
  - Exit

Use Exit from the tray menu when you want to fully close the background app.

### Start With Windows

On Windows, open Settings and enable Start with Windows if you want Wifi Chat Share to start automatically after sign-in.

This uses the current user's Windows startup registry entry, so it does not need Administrator permission. If you move the portable app folder to a different location, turn Start with Windows off and back on so Windows stores the new executable path.

### Windows Troubleshooting

If the app opens but another PC cannot send to it:

1. Run `Allow_WifiChatShare_Firewall.ps1` as Administrator on the receiving PC.
2. Make sure both devices are on the same Wi-Fi/LAN.
3. Check the app's **Ping IP** label and try `ping <that-ip-address>` from the other PC.
4. Keep the app open on both devices.
5. Try Refresh on both devices.
6. Run the included port test script from the release folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test_WifiChatShare_Port.ps1
```

If Windows says the app is corrupted, extract the whole ZIP again and run `wifi_chat_share.exe` from inside the extracted release folder.

## Android App

Current local APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Install With ADB

Enable Developer Options and USB debugging on the Android phone, connect it by USB, accept the RSA prompt on the phone, then run:

```powershell
.\android-sdk\platform-tools\adb.exe devices -l
.\android-sdk\platform-tools\adb.exe install -r .\build\app\outputs\flutter-apk\app-release.apk
```

### Install Manually

1. Copy `app-release.apk` to the Android phone.
2. Open the APK on the phone.
3. Allow install from this source if Android asks.
4. Open Wifi Chat Share.
5. Allow notification permission on Android 13+.
6. Keep the app open while testing discovery and transfers.

### Android Notes

- Both Android and desktop devices must be on the same Wi-Fi.
- Some phones pause background network activity aggressively. Keep the app visible while testing.
- Notifications are optional and can be changed from the app Settings.
- The app supports dark mode from the Settings screen.
- The Settings screen is compact and scrollable so it fits Android phones with large display/text settings.
- Open Settings and tap Add under Android Quick Settings tile to add the tile on Android 13+.
- The Quick Settings tile opens Wifi Chat Share when it is off and closes the app when tapped while active.
- On older Android versions, manually edit Quick Settings and drag the Wifi Chat Share tile into the active tile area if Android does not show the add prompt.

## iPhone / iPad App

iOS apps must be built on macOS with Xcode. You cannot create the final iPhone app package from Windows.

The iOS project files are included in this repository under:

```text
ios/
```

The project already includes local network, photo, documents, and notification permission text in `ios/Runner/Info.plist`.

### Build On Mac Mini Or Mac Desktop

Install:

- Xcode from the Mac App Store
- Flutter SDK
- CocoaPods
- Git

Then run:

```bash
git clone <your-github-repo-url>
cd wifi-chat-share
flutter doctor
flutter pub get
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```

In Xcode:

1. Select the Runner target.
2. Choose your Apple Developer Team.
3. Confirm or change the bundle identifier. The current default is `com.neolocal.wifichatshare`.
4. Connect a real iPhone.
5. Build and run from Xcode.
6. Allow local network and notification prompts on the phone.

Command-line release build:

```bash
flutter build ios --release
```

For TestFlight or App Store, archive from Xcode after signing is configured.

## macOS App

macOS apps must be built on a Mac with Xcode installed.

The macOS project files are included in:

```text
macos/
```

The macOS app has network client/server entitlement entries and permission text for local network, notifications, documents, downloads, and photos.

Build on a Mac:

```bash
git clone <your-github-repo-url>
cd wifi-chat-share
flutter config --enable-macos-desktop
flutter doctor
flutter pub get
flutter build macos --release
```

Output:

```text
build/macos/Build/Products/Release/Wifi Chat Share.app
```

Run the app, allow macOS firewall/network prompts, and enable notifications if macOS asks.

## Linux App

Install Flutter and Linux desktop build dependencies, then run:

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
```

Output:

```text
build/linux/x64/release/bundle/
```

If the Linux firewall is enabled, allow UDP `45872` and TCP `45873`.

## Developer Build Commands

From the project root:

```powershell
.\tools\flutter\bin\flutter.bat pub get
.\tools\flutter\bin\flutter.bat analyze
.\tools\flutter\bin\flutter.bat test
```

Windows:

```powershell
.\tools\flutter\bin\flutter.bat build windows --release
```

Android:

```powershell
.\tools\flutter\bin\flutter.bat build apk --release
```

macOS:

```bash
flutter build macos --release
```

iOS:

```bash
flutter build ios --release
```

Linux:

```bash
flutter build linux --release
```

## Windows Build Setup

For Windows desktop builds, enable Windows Developer Mode and install Visual Studio Build Tools with the Desktop development with C++ workload.

Because the original folder path contains a space, use the no-space junction for Flutter Windows builds:

```powershell
subst W: "D:\projects\wifi chat"
Set-Location W:\
.\tools\flutter\bin\flutter.bat pub get
.\tools\flutter\bin\flutter.bat build windows --release
```

You can also use this existing no-space junction if it exists:

```powershell
Set-Location "D:\projects\wifi_chat_build"
.\tools\flutter\bin\flutter.bat build windows --release
```

## GitHub And Mac Mini Workflow

After this project is pushed to GitHub, use the Mac mini to pull and build Apple apps.

First time on the Mac:

```bash
git clone <your-github-repo-url>
cd wifi-chat-share
flutter doctor
flutter pub get
```

Every time Windows changes are pushed:

```bash
cd wifi-chat-share
git pull --rebase
flutter pub get
```

Then build:

```bash
flutter build macos --release
flutter build ios --release
```

Open Xcode when you need signing, provisioning, TestFlight, App Store upload, or device-specific iPhone testing:

```bash
open ios/Runner.xcworkspace
open macos/Runner.xcworkspace
```

The app UI is shared Flutter code. Pull the latest GitHub version on the Mac mini before building iOS or macOS so the updated Settings layout, dark mode, notification options, and file-sharing UI are included in the Apple apps.

## Repository Notes

The GitHub repository should contain source code and platform project files. It should not contain local toolchains or generated builds.

Ignored local-only folders include:

- `tools/flutter/`
- `android-sdk/`
- `.pub-cache/`
- `.dart_tool/`
- `build/`
- `dist/`

Build the final Windows ZIP, Android APK, macOS app, and iOS archive from the checked-out source on the target machine.

## Troubleshooting

### Devices Do Not Appear

- Confirm every device is on the same Wi-Fi/LAN.
- Open the app on every device.
- Wait 5-10 seconds.
- Tap Refresh.
- Disable guest Wi-Fi or client isolation on the router.
- Allow local network prompts on iPhone/macOS.
- Allow firewall prompts on Windows/macOS/Linux.

### One-Way Messages Or File Transfers

- Run the Windows firewall script on the PC that is not receiving.
- Check that TCP `45873` is not blocked.
- Keep both apps open.
- Make sure VPN software is not routing local traffic away from Wi-Fi.

### Notifications Do Not Show

- Enable Notifications in the app Settings.
- On Android 13+, allow notification permission.
- On Windows/macOS, allow notifications in system settings.
- The app must be running to receive LAN messages.

### Received Files Are Hard To Find

- Open Settings and choose a received-files location.
- If no folder is selected, check the app's Documents location.

### iOS Or macOS Build Fails On Windows

This is expected. Apple apps require macOS and Xcode. Pull the GitHub repo on the Mac mini or Mac desktop, then build there.
