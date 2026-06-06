import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int discoveryPort = 45872;
const int transferPort = 45873;
const Color matrixGreen = Color(0xff00ff66);
const Color matrixDeepGreen = Color(0xff003b1f);
const Color matrixBlack = Color(0xff020403);

enum AppVisualTheme { light, dark, matrix }

extension AppVisualThemeX on AppVisualTheme {
  String get storageValue {
    switch (this) {
      case AppVisualTheme.light:
        return 'light';
      case AppVisualTheme.dark:
        return 'dark';
      case AppVisualTheme.matrix:
        return 'matrix';
    }
  }

  static AppVisualTheme? fromStorage(String? value) {
    switch (value) {
      case 'light':
        return AppVisualTheme.light;
      case 'dark':
        return AppVisualTheme.dark;
      case 'matrix':
        return AppVisualTheme.matrix;
      default:
        return null;
    }
  }
}

ThemeData _themeFor(AppVisualTheme visualTheme) {
  switch (visualTheme) {
    case AppVisualTheme.light:
      return _lightTheme();
    case AppVisualTheme.dark:
      return _darkTheme();
    case AppVisualTheme.matrix:
      return _matrixTheme();
  }
}

ThemeData _lightTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f766e)),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );
}

ThemeData _darkTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff14b8a6),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );
}

ThemeData _matrixTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: matrixGreen,
    brightness: Brightness.dark,
  ).copyWith(
    primary: matrixGreen,
    onPrimary: matrixBlack,
    primaryContainer: const Color(0xff053f21),
    onPrimaryContainer: const Color(0xffd9ffe6),
    secondary: const Color(0xff7cffaa),
    onSecondary: matrixBlack,
    secondaryContainer: const Color(0xff072d19),
    onSecondaryContainer: const Color(0xffc9ffdc),
    surface: const Color(0xff050806),
    onSurface: const Color(0xffd8ffe4),
    surfaceContainerLowest: const Color(0xff020403),
    surfaceContainerLow: const Color(0xff07110a),
    surfaceContainer: const Color(0xff0a160d),
    surfaceContainerHigh: const Color(0xff0d1f12),
    surfaceContainerHighest: const Color(0xff112818),
    onSurfaceVariant: const Color(0xffa3e8b8),
    outline: const Color(0xff2b3a32),
    outlineVariant: const Color(0xff1b2420),
    error: const Color(0xffff6b6b),
    onError: matrixBlack,
    errorContainer: const Color(0xff4a0909),
    onErrorContainer: const Color(0xffffd7d7),
  );

  final base = ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: matrixBlack,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    fontFamily: 'monospace',
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xff090b0c),
      foregroundColor: const Color(0xffd8ffe4),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: const Color(0xffd8ffe4),
        fontWeight: FontWeight.w800,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xff061008),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xff202725)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xff202725)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff061008),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff202725)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff202725)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: matrixGreen, width: 1.5),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: matrixGreen,
      textColor: Color(0xffd8ffe4),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xff062d17),
      contentTextStyle: TextStyle(color: Color(0xffd8ffe4)),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const WifiChatShareApp());
}

class WifiChatShareApp extends StatefulWidget {
  const WifiChatShareApp({super.key});

  @override
  State<WifiChatShareApp> createState() => _WifiChatShareAppState();
}

class _WifiChatShareAppState extends State<WifiChatShareApp> {
  AppVisualTheme visualTheme = AppVisualTheme.light;
  bool notificationsEnabled = true;
  bool startAtStartup = false;
  String? downloadDirectory;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      final savedTheme = prefs.getString('visualTheme');
      visualTheme = AppVisualThemeX.fromStorage(savedTheme) ??
          ((prefs.getBool('darkMode') ?? false) ? AppVisualTheme.dark : AppVisualTheme.light);
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      startAtStartup = prefs.getBool('startAtStartup') ?? false;
      downloadDirectory = prefs.getString('downloadDirectory');
    });
    await NotificationService.instance.setEnabled(notificationsEnabled);
    if (Platform.isWindows && startAtStartup) {
      await WindowsStartupService.instance.setEnabled(true);
    }
  }

  Future<void> _setVisualTheme(AppVisualTheme value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('visualTheme', value.storageValue);
    await prefs.setBool('darkMode', value == AppVisualTheme.dark || value == AppVisualTheme.matrix);
    setState(() => visualTheme = value);
  }

  Future<void> _setDownloadDirectory(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove('downloadDirectory');
      setState(() => downloadDirectory = null);
      return;
    }
    await prefs.setString('downloadDirectory', path);
    setState(() => downloadDirectory = path);
  }

  Future<void> _setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', value);
    await NotificationService.instance.setEnabled(value);
    setState(() => notificationsEnabled = value);
  }

  Future<void> _setStartAtStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final applied = await WindowsStartupService.instance.setEnabled(value);
    await prefs.setBool('startAtStartup', applied);
    if (!mounted) {
      return;
    }
    setState(() => startAtStartup = applied);
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = _themeFor(visualTheme);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wifi Chat Share',
      theme: activeTheme,
      themeMode: ThemeMode.light,
      home: HomeScreen(
        visualTheme: visualTheme,
        downloadDirectory: downloadDirectory,
        notificationsEnabled: notificationsEnabled,
        startAtStartup: startAtStartup,
        onVisualThemeChanged: _setVisualTheme,
        onDownloadDirectoryChanged: _setDownloadDirectory,
        onNotificationsChanged: _setNotificationsEnabled,
        onStartAtStartupChanged: _setStartAtStartup,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.visualTheme,
    required this.downloadDirectory,
    required this.notificationsEnabled,
    required this.startAtStartup,
    required this.onVisualThemeChanged,
    required this.onDownloadDirectoryChanged,
    required this.onNotificationsChanged,
    required this.onStartAtStartupChanged,
    super.key,
  });

  final AppVisualTheme visualTheme;
  final String? downloadDirectory;
  final bool notificationsEnabled;
  final bool startAtStartup;
  final ValueChanged<AppVisualTheme> onVisualThemeChanged;
  final ValueChanged<String?> onDownloadDirectoryChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onStartAtStartupChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final LanChatService service;
  String? selectedPeerId;
  final TextEditingController messageController = TextEditingController();
  final FocusNode messageFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    service = LanChatService(downloadDirectory: widget.downloadDirectory)..start();
    WindowsTrayBridge.instance.attach(service);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadDirectory != widget.downloadDirectory) {
      service.setDownloadDirectory(widget.downloadDirectory);
    }
  }

  @override
  void dispose() {
    WindowsTrayBridge.instance.detach(service);
    messageFocusNode.dispose();
    messageController.dispose();
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final peers = service.visiblePeers;
        final selectedPeer = selectedPeerId == null ? null : service.peers[selectedPeerId];
        final body = LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 760;
            if (isCompact) {
              return Column(
                children: [
                  StatusBar(text: service.lastStatus, networkText: service.pingAddressLabel),
                  Expanded(
                    child: selectedPeer == null
                        ? PeerList(
                            peers: peers,
                            selectedPeerId: selectedPeerId,
                            onSelect: (peer) => setState(() => selectedPeerId = peer.id),
                            onRemovePeer: _removePeer,
                            onClearPeers: _clearPeers,
                          )
                        : ChatPane(
                            service: service,
                            peer: selectedPeer,
                            controller: messageController,
                            focusNode: messageFocusNode,
                            onBack: () => setState(() => selectedPeerId = null),
                          ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                StatusBar(text: service.lastStatus, networkText: service.pingAddressLabel),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 330,
                        child: PeerList(
                          peers: peers,
                          selectedPeerId: selectedPeerId,
                          onSelect: (peer) => setState(() => selectedPeerId = peer.id),
                          onRemovePeer: _removePeer,
                          onClearPeers: _clearPeers,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selectedPeer == null
                            ? EmptyState(
                                isRunning: service.isRunning,
                                deviceName: service.localName,
                                pingAddressLabel: service.pingAddressLabel,
                              )
                            : ChatPane(
                                service: service,
                                peer: selectedPeer,
                                controller: messageController,
                                focusNode: messageFocusNode,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Wifi Chat Share'),
            actions: [
              IconButton(
                tooltip: service.isRunning ? 'Online' : 'Start discovery',
                onPressed: service.isRunning ? null : service.start,
                icon: Icon(service.isRunning ? Icons.wifi_tethering : Icons.wifi_off),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: service.refreshNow,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: _showSettings,
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          body: widget.visualTheme == AppVisualTheme.matrix ? MatrixBackdrop(child: body) : body,
        );
      },
    );
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        visualTheme: widget.visualTheme,
        downloadDirectory: widget.downloadDirectory,
        notificationsEnabled: widget.notificationsEnabled,
        startAtStartup: widget.startAtStartup,
        onVisualThemeChanged: widget.onVisualThemeChanged,
        onDownloadDirectoryChanged: widget.onDownloadDirectoryChanged,
        onNotificationsChanged: widget.onNotificationsChanged,
        onStartAtStartupChanged: widget.onStartAtStartupChanged,
      ),
    );
  }

  void _removePeer(PeerDevice peer) {
    service.removePeer(peer.id);
    if (selectedPeerId == peer.id) {
      setState(() => selectedPeerId = null);
    }
  }

  void _clearPeers() {
    service.clearPeers();
    setState(() => selectedPeerId = null);
  }
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    required this.visualTheme,
    required this.downloadDirectory,
    required this.notificationsEnabled,
    required this.startAtStartup,
    required this.onVisualThemeChanged,
    required this.onDownloadDirectoryChanged,
    required this.onNotificationsChanged,
    required this.onStartAtStartupChanged,
    super.key,
  });

  final AppVisualTheme visualTheme;
  final String? downloadDirectory;
  final bool notificationsEnabled;
  final bool startAtStartup;
  final ValueChanged<AppVisualTheme> onVisualThemeChanged;
  final ValueChanged<String?> onDownloadDirectoryChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onStartAtStartupChanged;

  @override
  Widget build(BuildContext context) {
    final effectivePath = downloadDirectory ?? 'Documents / app documents';
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final compactText = mediaQuery.copyWith(
      textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.18),
    );

    return MediaQuery(
      data: compactText,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Settings',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Done',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Theme'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SegmentedButton<AppVisualTheme>(
                          segments: const [
                            ButtonSegment(
                              value: AppVisualTheme.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: AppVisualTheme.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                            ButtonSegment(
                              value: AppVisualTheme.matrix,
                              icon: Icon(Icons.code),
                              label: Text('Matrix'),
                            ),
                          ],
                          selected: {visualTheme},
                          onSelectionChanged: (values) => onVisualThemeChanged(values.single),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: const Text('Notifications'),
                      subtitle: const Text('Popups for chats and files'),
                      value: notificationsEnabled,
                      onChanged: onNotificationsChanged,
                    ),
                    if (Platform.isWindows)
                      SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        title: const Text('Start with Windows'),
                        subtitle: const Text('Open when you sign in'),
                        value: startAtStartup,
                        onChanged: onStartAtStartupChanged,
                      ),
                    if (Platform.isWindows)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: const Icon(Icons.security_outlined),
                        title: const Text('Allow firewall'),
                        subtitle: const Text('Requires Administrator permission'),
                        trailing: FilledButton.tonal(
                          onPressed: () => WindowsDesktopTools.instance.runFirewallScript(),
                          child: const Text('Run'),
                        ),
                      ),
                    if (Platform.isWindows)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: const Icon(Icons.network_ping_outlined),
                        title: const Text('Test peer port'),
                        subtitle: const Text('No Administrator permission needed'),
                        trailing: FilledButton.tonal(
                          onPressed: () => WindowsDesktopTools.instance.runPortTestScript(),
                          child: const Text('Run'),
                        ),
                      ),
                    if (Platform.isAndroid)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: const Icon(Icons.flash_on_outlined),
                        title: const Text('Quick Settings tile'),
                        subtitle: const Text('Open or close from Android controls'),
                        trailing: FilledButton.tonal(
                          onPressed: AndroidQuickSettingsService.instance.requestTile,
                          child: const Text('Add'),
                        ),
                      ),
                    const Divider(height: 24),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Received files'),
                      subtitle: Text(
                        effectivePath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
              children: [
                  TextButton(
                    onPressed: () => onDownloadDirectoryChanged(null),
                    child: const Text('Use default'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose'),
                    onPressed: () async {
                      final path = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'Choose received files folder',
                      );
                      if (path != null) {
                        onDownloadDirectoryChanged(path);
                      }
                    },
                  ),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MatrixBackdrop extends StatelessWidget {
  const MatrixBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/matrix_background.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: matrixBlack.withAlpha(160),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  matrixBlack.withAlpha(105),
                  matrixBlack.withAlpha(170),
                  matrixBlack.withAlpha(225),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class StatusBar extends StatelessWidget {
  const StatusBar({required this.text, required this.networkText, super.key});

  final String text;
  final String networkText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              networkText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class PeerList extends StatelessWidget {
  const PeerList({
    required this.peers,
    required this.selectedPeerId,
    required this.onSelect,
    required this.onRemovePeer,
    required this.onClearPeers,
    super.key,
  });

  final List<PeerDevice> peers;
  final String? selectedPeerId;
  final ValueChanged<PeerDevice> onSelect;
  final ValueChanged<PeerDevice> onRemovePeer;
  final VoidCallback onClearPeers;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nearby devices',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (peers.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear nearby devices',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: onClearPeers,
                  ),
              ],
            ),
          ),
          Expanded(
            child: peers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No devices found yet. Keep this app open on another device connected to the same Wi-Fi.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemBuilder: (context, index) {
                      final peer = peers[index];
                      final selected = selectedPeerId == peer.id;
                      return GestureDetector(
                        key: ValueKey(peer.id),
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) => _showPeerMenu(context, peer, details.globalPosition),
                        onLongPressStart: (details) => _showPeerMenu(context, peer, details.globalPosition),
                        child: ListTile(
                          selected: selected,
                          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          leading: CircleAvatar(
                            child: Icon(_platformIcon(peer.platform)),
                          ),
                          title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${peer.platformLabel} • ${peer.address.address}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(peer.isFresh ? Icons.circle : Icons.schedule, size: 14),
                              PopupMenuButton<String>(
                                tooltip: 'Device options',
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    onRemovePeer(peer);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline),
                                        SizedBox(width: 10),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => onSelect(peer),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemCount: peers.length,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPeerMenu(BuildContext context, PeerDevice peer, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline),
              SizedBox(width: 10),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
    if (selected == 'delete') {
      onRemovePeer(peer);
    }
  }
}

class ChatPane extends StatelessWidget {
  const ChatPane({
    required this.service,
    required this.peer,
    required this.controller,
    required this.focusNode,
    this.onBack,
    super.key,
  });

  final LanChatService service;
  final PeerDevice peer;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final messages = service.messagesFor(peer.id);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              leading: onBack == null
                  ? CircleAvatar(child: Icon(_platformIcon(peer.platform)))
                  : IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: onBack,
                    ),
              title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${peer.platformLabel} • ${peer.address.address}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Send file, image, ZIP, or document',
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => service.pickAndSendFile(peer),
                  ),
                  IconButton(
                    tooltip: 'Send folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => service.pickAndSendFolder(peer),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('Send a message or attach a file.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - index - 1];
                    return MessageBubble(message: message);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach file, image, ZIP, or document',
                  icon: const Icon(Icons.attach_file),
                  onPressed: () => service.pickAndSendFile(peer),
                ),
                IconButton(
                  tooltip: 'Attach folder',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: () => service.pickAndSendFolder(peer),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendText,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _sendText() {
    final text = controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    controller.clear();
    service.sendText(peer, text);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      focusNode.requestFocus();
    }
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final align = message.outgoing ? Alignment.centerRight : Alignment.centerLeft;
    final isSystem = message.kind == MessageKind.system;
    final isAttachment = message.kind == MessageKind.file || message.kind == MessageKind.folder;
    final copyText = _copyTextForMessage(message);
    final background = isSystem
        ? colorScheme.errorContainer
        : message.outgoing
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest;
    final foreground = isSystem
        ? colorScheme.onErrorContainer
        : message.outgoing
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: isAttachment
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                message.kind == MessageKind.folder
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  message.fileName ?? (message.kind == MessageKind.folder ? 'Folder' : 'File'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          )
                        : SelectableText(
                            message.text,
                            style: TextStyle(color: foreground),
                          ),
                  ),
                  if (copyText.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    CopyMessageButton(
                      text: copyText,
                      foreground: foreground,
                    ),
                  ],
                ],
              ),
              if (isAttachment && message.filePath != null) ...[
                const SizedBox(height: 6),
                SelectableText(
                  message.filePath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: foreground.withAlpha(191)),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _timeLabel(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground.withAlpha(178)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CopyMessageButton extends StatelessWidget {
  const CopyMessageButton({
    required this.text,
    required this.foreground,
    super.key,
  });

  final String text;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy',
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: foreground.withAlpha(204),
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied')),
            );
          }
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.isRunning,
    required this.deviceName,
    required this.pingAddressLabel,
    super.key,
  });

  final bool isRunning;
  final String deviceName;
  final String pingAddressLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRunning ? Icons.devices_other : Icons.wifi_off,
                size: 58,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                deviceName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                pingAddressLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open Wifi Chat Share on another device connected to this network. Devices will appear automatically.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LanChatService extends ChangeNotifier {
  LanChatService({String? downloadDirectory})
      : localId = _makeId(),
        localName = _localDeviceName(),
        _downloadDirectory = downloadDirectory;

  final String localId;
  final String localName;
  final Map<String, PeerDevice> peers = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Set<String> _hiddenPeerIds = {};
  String? _downloadDirectory;
  List<String> _localIPv4AddressText = const [];
  String lastStatus = 'Starting...';

  RawDatagramSocket? _udpSocket;
  ServerSocket? _server;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  Timer? _healthTimer;
  bool _bindingDiscovery = false;
  bool _bindingServer = false;
  bool _disposed = false;
  bool isRunning = false;

  String get pingAddressLabel {
    if (_localIPv4AddressText.isEmpty) {
      return 'Ping IP: checking...';
    }
    return 'Ping IP: ${_localIPv4AddressText.join(', ')}';
  }

  void _setStatus(String value, {bool notify = true}) {
    if (lastStatus == value) {
      return;
    }
    lastStatus = value;
    if (notify) {
      notifyListeners();
    }
  }

  List<PeerDevice> get visiblePeers {
    final values = peers.values.toList()
      ..sort((a, b) {
        final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (name != 0) {
          return name;
        }
        return a.address.address.compareTo(b.address.address);
      });
    return values;
  }

  Future<void> start() async {
    if (isRunning) {
      return;
    }

    await _requestPermissions();
    await _refreshLocalAddresses(notify: false);
    await _bindDiscoverySocket();
    await _bindTransferServer();

    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) => broadcastNow());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) => _removeStalePeers());
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) => _ensureSocketsHealthy());
    isRunning = true;
    if (_server != null) {
      lastStatus = 'Online as $localName on ports $discoveryPort/$transferPort';
    }
    notifyListeners();
    broadcastNow();
  }

  Future<void> _bindDiscoverySocket() async {
    if (_udpSocket != null || _bindingDiscovery || _disposed) {
      return;
    }
    _bindingDiscovery = true;
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen(
        _handleDiscoveryEvent,
        onError: (Object error) {
          _udpSocket?.close();
          _udpSocket = null;
          lastStatus = 'Discovery socket recovering: ${_shortError(error)}';
          notifyListeners();
        },
        onDone: () {
          _udpSocket = null;
          if (!_disposed) {
            lastStatus = 'Discovery socket closed; reconnecting...';
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      lastStatus = 'Discovery port unavailable: ${_shortError(error)}';
      notifyListeners();
    } finally {
      _bindingDiscovery = false;
    }
  }

  Future<void> _bindTransferServer() async {
    if (_server != null || _bindingServer || _disposed) {
      return;
    }
    _bindingServer = true;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort, shared: true);
      _server?.listen(
        _handleIncomingSocket,
        onError: (Object error) {
          _server?.close();
          _server = null;
          lastStatus = 'Transfer listener recovering: ${_shortError(error)}';
          notifyListeners();
        },
        onDone: () {
          _server = null;
          if (!_disposed) {
            lastStatus = 'Transfer listener closed; reconnecting...';
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      lastStatus = 'Transfer port unavailable: close other Wifi Chat Share windows and restart';
      notifyListeners();
    } finally {
      _bindingServer = false;
    }
  }

  Future<void> _ensureSocketsHealthy() async {
    if (_disposed) {
      return;
    }
    await _bindDiscoverySocket();
    await _bindTransferServer();
    await _refreshLocalAddresses();
    if (_udpSocket != null && _server != null && isRunning) {
      broadcastNow();
    }
  }

  Future<void> _refreshLocalAddresses({bool notify = true}) async {
    final addresses = (await _localIPv4Addresses())
        .map((address) => address.address)
        .toSet()
        .toList()
      ..sort();
    final old = _localIPv4AddressText.join('|');
    final updated = addresses.join('|');
    if (old == updated) {
      return;
    }
    _localIPv4AddressText = addresses;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> broadcastNow() async {
    if (_udpSocket == null) {
      await _bindDiscoverySocket();
    }
    final socket = _udpSocket;
    if (socket == null) {
      lastStatus = 'Discovery is reconnecting...';
      notifyListeners();
      return;
    }

    final payload = utf8.encode(jsonEncode({
      'type': 'hello',
      'id': localId,
      'name': localName,
      'platform': _platformName(),
      'port': transferPort,
      'time': DateTime.now().toIso8601String(),
    }));

    try {
      for (final address in await _broadcastTargets()) {
        socket.send(payload, address, discoveryPort);
      }
    } catch (error) {
      socket.close();
      _udpSocket = null;
      _setStatus('Discovery send failed; reconnecting: ${_shortError(error)}');
    }
  }

  List<ChatMessage> messagesFor(String peerId) => List.unmodifiable(_messages[peerId] ?? const []);

  void setDownloadDirectory(String? path) {
    _downloadDirectory = path;
    lastStatus = path == null ? 'Received files will save to Documents' : 'Received files will save to $path';
    notifyListeners();
  }

  void removePeer(String peerId) {
    final peer = peers.remove(peerId);
    if (peer == null) {
      return;
    }
    _hiddenPeerIds.add(peerId);
    lastStatus = 'Removed ${peer.name} from nearby devices';
    notifyListeners();
  }

  void clearPeers() {
    final count = peers.length;
    _hiddenPeerIds.addAll(peers.keys);
    peers.clear();
    lastStatus = count == 0 ? 'Nearby devices list is already empty' : 'Cleared $count nearby device(s)';
    notifyListeners();
  }

  Future<void> refreshNow() async {
    _hiddenPeerIds.clear();
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));

    if (_server == null) {
      await _bindTransferServer();
    }
    if (_udpSocket == null) {
      await _bindDiscoverySocket();
    }
    await _refreshLocalAddresses(notify: false);
    await broadcastNow();

    lastStatus = peers.isEmpty ? 'Refreshed; waiting for nearby devices' : 'Refreshed ${peers.length} nearby device(s)';
    notifyListeners();
  }

  Future<void> sendText(PeerDevice peer, String text) async {
    final message = ChatMessage(
      id: _makeId(),
      peerId: peer.id,
      text: text,
      kind: MessageKind.text,
      outgoing: true,
      createdAt: DateTime.now(),
    );
    _messages.putIfAbsent(peer.id, () => []).add(message);
    notifyListeners();

    try {
      await _sendEnvelope(peer, {
        'type': 'chat',
        'id': message.id,
        'fromId': localId,
        'fromName': localName,
        'text': text,
        'createdAt': message.createdAt.toIso8601String(),
      });
      lastStatus = 'Message sent to ${peer.name}';
      notifyListeners();
    } catch (error) {
      broadcastNow();
      _messages[peer.id]?.add(
        ChatMessage(
          id: _makeId(),
          peerId: peer.id,
          text: 'Send failed: ${_shortError(error)}',
          kind: MessageKind.system,
          outgoing: true,
          createdAt: DateTime.now(),
        ),
      );
      lastStatus = 'Send failed to ${peer.name}: ${_shortError(error)}';
      notifyListeners();
    }
  }

  Future<void> pickAndSendFile(PeerDevice peer) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await sendFile(peer, File(path));
  }

  Future<void> pickAndSendFolder(PeerDevice peer) async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose folder to send');
    if (path == null) {
      return;
    }
    await sendFolder(peer, Directory(path));
  }

  Future<void> sendFile(PeerDevice peer, File file) async {
    final bytes = await file.readAsBytes();
    final name = file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last;
    final message = ChatMessage(
      id: _makeId(),
      peerId: peer.id,
      text: 'Sent $name',
      kind: MessageKind.file,
      outgoing: true,
      fileName: name,
      filePath: file.path,
      createdAt: DateTime.now(),
    );
    _messages.putIfAbsent(peer.id, () => []).add(message);
    notifyListeners();

    try {
      await _sendEnvelope(
        peer,
        {
          'type': 'file',
          'id': message.id,
          'fromId': localId,
          'fromName': localName,
          'fileName': name,
          'byteLength': bytes.length,
          'createdAt': message.createdAt.toIso8601String(),
        },
        bytes,
      );
      lastStatus = 'File sent to ${peer.name}: $name';
      notifyListeners();
    } catch (error) {
      broadcastNow();
      _messages[peer.id]?.add(
        ChatMessage(
          id: _makeId(),
          peerId: peer.id,
          text: 'File send failed: ${_shortError(error)}',
          kind: MessageKind.system,
          outgoing: true,
          createdAt: DateTime.now(),
        ),
      );
      lastStatus = 'File send failed to ${peer.name}: ${_shortError(error)}';
      notifyListeners();
    }
  }

  Future<void> sendFolder(PeerDevice peer, Directory directory) async {
    final name = _safeFileName(_folderNameFromPath(directory.path));
    final message = ChatMessage(
      id: _makeId(),
      peerId: peer.id,
      text: 'Sent folder $name',
      kind: MessageKind.folder,
      outgoing: true,
      fileName: name,
      filePath: directory.path,
      createdAt: DateTime.now(),
    );
    _messages.putIfAbsent(peer.id, () => []).add(message);
    notifyListeners();

    try {
      final bytes = await _zipDirectory(directory);
      await _sendEnvelope(
        peer,
        {
          'type': 'folder',
          'id': message.id,
          'fromId': localId,
          'fromName': localName,
          'folderName': name,
          'byteLength': bytes.length,
          'createdAt': message.createdAt.toIso8601String(),
        },
        bytes,
      );
      lastStatus = 'Folder sent to ${peer.name}: $name';
      notifyListeners();
    } catch (error) {
      broadcastNow();
      _messages[peer.id]?.add(
        ChatMessage(
          id: _makeId(),
          peerId: peer.id,
          text: 'Folder send failed: ${_shortError(error)}',
          kind: MessageKind.system,
          outgoing: true,
          createdAt: DateTime.now(),
        ),
      );
      lastStatus = 'Folder send failed to ${peer.name}: ${_shortError(error)}';
      notifyListeners();
    }
  }

  Future<void> _sendEnvelope(PeerDevice peer, Map<String, Object?> header, [Uint8List? body]) async {
    final socket = await Socket.connect(peer.address, peer.port, timeout: const Duration(seconds: 8));
    try {
      final headerBytes = utf8.encode('${jsonEncode(header)}\n');
      socket.add(headerBytes);
      if (body != null) {
        const chunkSize = 64 * 1024;
        for (var offset = 0; offset < body.length; offset += chunkSize) {
          final end = min(offset + chunkSize, body.length);
          socket.add(Uint8List.sublistView(body, offset, end));
          if (offset % (1024 * 1024) == 0) {
            await socket.flush();
          }
        }
      }
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  void _handleDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final datagram = _udpSocket?.receive();
    if (datagram == null) {
      return;
    }

    try {
      final payload = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (payload['type'] != 'hello' || payload['id'] == localId) {
        return;
      }

      final id = payload['id'] as String;
      if (_hiddenPeerIds.contains(id)) {
        return;
      }
      final existing = peers[id];
      final updated = PeerDevice(
        id: id,
        name: (payload['name'] as String?)?.trim().isNotEmpty == true ? payload['name'] as String : 'Unknown device',
        platform: payload['platform'] as String? ?? 'unknown',
        address: datagram.address,
        port: payload['port'] as int? ?? transferPort,
        lastSeen: DateTime.now(),
      );
      peers[id] = updated;

      final changed = existing == null ||
          existing.name != updated.name ||
          existing.platform != updated.platform ||
          existing.address.address != updated.address.address ||
          existing.port != updated.port;
      if (changed) {
        _setStatus('Found ${updated.name} at ${datagram.address.address}', notify: false);
        notifyListeners();
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _handleIncomingSocket(Socket socket) async {
    File? temporaryBodyFile;
    try {
      final envelope = await _readIncomingEnvelope(socket);
      temporaryBodyFile = envelope.bodyFile;
      final header = envelope.header;
      final fromId = header['fromId'] as String? ?? socket.remoteAddress.address;
      final fromName = header['fromName'] as String? ?? socket.remoteAddress.address;

      peers.putIfAbsent(
        fromId,
        () => PeerDevice(
          id: fromId,
          name: fromName,
          platform: 'unknown',
          address: socket.remoteAddress,
          port: transferPort,
          lastSeen: DateTime.now(),
        ),
      );

      if (header['type'] == 'chat') {
        final text = header['text'] as String? ?? '';
        _messages.putIfAbsent(fromId, () => []).add(
              ChatMessage(
                id: header['id'] as String? ?? _makeId(),
                peerId: fromId,
                text: text,
                kind: MessageKind.text,
                outgoing: false,
                createdAt: DateTime.tryParse(header['createdAt'] as String? ?? '') ?? DateTime.now(),
              ),
            );
        lastStatus = 'Message received from $fromName';
        NotificationService.instance.showMessage(fromName: fromName, text: text);
      }

      if (header['type'] == 'file') {
        final fileName = _safeFileName(header['fileName'] as String? ?? 'received-file');
        final bodyFile = envelope.bodyFile;
        if (bodyFile == null) {
          throw const FileSystemException('Missing received file body');
        }
        final incomingDir = await _incomingDirectory();
        if (!await incomingDir.exists()) {
          await incomingDir.create(recursive: true);
        }
        final file = File('${incomingDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}-$fileName');
        await bodyFile.copy(file.path);

        _messages.putIfAbsent(fromId, () => []).add(
              ChatMessage(
                id: header['id'] as String? ?? _makeId(),
                peerId: fromId,
                text: 'Received $fileName',
                kind: MessageKind.file,
                outgoing: false,
                fileName: fileName,
                filePath: file.path,
                createdAt: DateTime.tryParse(header['createdAt'] as String? ?? '') ?? DateTime.now(),
              ),
            );
        lastStatus = 'File received from $fromName: $fileName';
        NotificationService.instance.showFile(fromName: fromName, fileName: fileName);
      }

      if (header['type'] == 'folder') {
        final folderName = _safeFileName(header['folderName'] as String? ?? 'received-folder');
        final bodyFile = envelope.bodyFile;
        if (bodyFile == null) {
          throw const FileSystemException('Missing received folder body');
        }
        final incomingDir = await _incomingDirectory();
        if (!await incomingDir.exists()) {
          await incomingDir.create(recursive: true);
        }
        final folder = Directory(
          '${incomingDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}-$folderName',
        );
        await _extractFolderArchive(bodyFile, folder);

        _messages.putIfAbsent(fromId, () => []).add(
              ChatMessage(
                id: header['id'] as String? ?? _makeId(),
                peerId: fromId,
                text: 'Received folder $folderName',
                kind: MessageKind.folder,
                outgoing: false,
                fileName: folderName,
                filePath: folder.path,
                createdAt: DateTime.tryParse(header['createdAt'] as String? ?? '') ?? DateTime.now(),
              ),
            );
        lastStatus = 'Folder received from $fromName: $folderName';
        NotificationService.instance.showFolder(fromName: fromName, folderName: folderName);
      }

      notifyListeners();
    } catch (error) {
      lastStatus = 'Ignored dropped connection: ${_shortError(error)}';
      notifyListeners();
    } finally {
      try {
        await temporaryBodyFile?.delete();
      } catch (_) {
        // Temporary transfer cleanup can be skipped if the OS already removed it.
      }
      socket.destroy();
    }
  }

  Future<Directory> _incomingDirectory() async {
    final configured = _downloadDirectory;
    if (configured != null && configured.trim().isNotEmpty) {
      return Directory(configured);
    }
    final directory = await getApplicationDocumentsDirectory();
    return Directory('${directory.path}${Platform.pathSeparator}WifiChatShare');
  }

  Future<Uint8List> _zipDirectory(Directory directory) async {
    if (!await directory.exists()) {
      throw FileSystemException('Folder not found', directory.path);
    }

    final archive = Archive();
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      final relativePath = _relativeArchivePath(directory.path, entity.path);
      if (relativePath.isEmpty) {
        continue;
      }
      if (entity is Directory) {
        archive.addFile(ArchiveFile.directory(relativePath));
      } else if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  Future<void> _extractFolderArchive(File zipFile, Directory folder) async {
    await folder.create(recursive: true);
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive.files) {
        final relativePath = _safeArchiveEntryPath(entry.name);
        if (relativePath == null) {
          continue;
        }
        final path = '${folder.path}${Platform.pathSeparator}$relativePath';
        if (entry.isDirectory) {
          await Directory(path).create(recursive: true);
        } else if (entry.isFile) {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.content);
        }
      }
    } finally {
      await input.close();
    }
  }

  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    for (final peer in peers.values) {
      targets.add(peer.address.address);
    }
    for (final address in await _localIPv4Addresses()) {
      final parts = address.address.split('.');
      if (parts.length == 4) {
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
    return targets.map(InternetAddress.new).toList(growable: false);
  }

  Future<IncomingEnvelope> _readIncomingEnvelope(Socket socket) async {
    final headerBuilder = BytesBuilder(copy: false);
    Map<String, dynamic>? header;
    File? bodyFile;
    IOSink? bodySink;
    var expectedBodyLength = 0;
    var receivedBodyLength = 0;

    await for (final chunk in socket) {
      var bodyStart = 0;
      if (header == null) {
        final split = chunk.indexOf(10);
        if (split < 0) {
          headerBuilder.add(chunk);
          continue;
        }

        if (split > 0) {
          headerBuilder.add(Uint8List.sublistView(chunk, 0, split));
        }
        header = jsonDecode(utf8.decode(headerBuilder.takeBytes())) as Map<String, dynamic>;
        expectedBodyLength = header['byteLength'] as int? ?? 0;
        if (expectedBodyLength > 0) {
          bodyFile = await _createTransferTempFile();
          bodySink = bodyFile.openWrite();
        }
        bodyStart = split + 1;
      }

      final sink = bodySink;
      if (sink != null && bodyStart < chunk.length) {
        final data = Uint8List.sublistView(chunk, bodyStart);
        sink.add(data);
        receivedBodyLength += data.length;
      }
    }

    await bodySink?.flush();
    await bodySink?.close();

    final parsedHeader = header;
    if (parsedHeader == null) {
      throw const FormatException('Missing transfer header');
    }
    if (expectedBodyLength > 0 && receivedBodyLength != expectedBodyLength) {
      throw FormatException('Incomplete transfer: received $receivedBodyLength of $expectedBodyLength bytes');
    }
    return IncomingEnvelope(header: parsedHeader, bodyFile: bodyFile);
  }

  Future<File> _createTransferTempFile() async {
    final directory = await getTemporaryDirectory();
    final transferDir = Directory('${directory.path}${Platform.pathSeparator}WifiChatShareTransfers');
    if (!await transferDir.exists()) {
      await transferDir.create(recursive: true);
    }
    return File('${transferDir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-${_makeId()}.bin');
  }

  void _removeStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    final before = peers.length;
    peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
    if (peers.length != before) {
      notifyListeners();
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
        Permission.storage,
        Permission.photos,
        Permission.videos,
      ].request();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _healthTimer?.cancel();
    _udpSocket?.close();
    _server?.close();
    super.dispose();
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _enabled = true;
  int _nextId = 1;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    try {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Wifi Chat Share',
          appUserModelId: 'com.neoapps.wifichatshare',
          guid: '8d99c1d4-5424-45ce-b4f6-0215684b3c1d',
        ),
      );

      await _plugin.initialize(settings: initializationSettings);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!_enabled) {
      return;
    }
    await init();
    await _requestPermission();
  }

  Future<void> showMessage({required String fromName, required String text}) async {
    await _show(
      title: 'Message from $fromName',
      body: text.isEmpty ? 'New message' : text,
    );
  }

  Future<void> showFile({required String fromName, required String fileName}) async {
    await _show(
      title: 'File from $fromName',
      body: fileName,
    );
  }

  Future<void> showFolder({required String fromName, required String folderName}) async {
    await _show(
      title: 'Folder from $fromName',
      body: folderName,
    );
  }

  Future<void> _show({required String title, required String body}) async {
    if (!_enabled) {
      return;
    }
    await init();
    if (!_initialized) {
      return;
    }

    final safeBody = body.length > 180 ? '${body.substring(0, 177)}...' : body;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: safeBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'wifi_chat_share_events',
            'Wifi Chat Share',
            channelDescription: 'Incoming chat messages and shared files',
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(
            duration: WindowsNotificationDuration.short,
          ),
        ),
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      return;
    }
  }
}

class WindowsTrayBridge {
  WindowsTrayBridge._();

  static final WindowsTrayBridge instance = WindowsTrayBridge._();

  static const MethodChannel _channel = MethodChannel('wifi_chat_share/tray');

  LanChatService? _service;
  VoidCallback? _listener;

  Future<void> attach(LanChatService service) async {
    if (!Platform.isWindows) {
      return;
    }
    detach(_service);
    _service = service;
    _listener = () => _updatePeers(service);
    service.addListener(_listener!);
    _channel.setMethodCallHandler(_handleMethodCall);
    await _updatePeers(service);
  }

  void detach(LanChatService? service) {
    if (!Platform.isWindows || service == null || service != _service) {
      return;
    }
    final listener = _listener;
    if (listener != null) {
      service.removeListener(listener);
    }
    _listener = null;
    _service = null;
    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'trayRefresh':
        await _service?.refreshNow();
        return null;
      default:
        throw MissingPluginException('Unknown tray method ${call.method}');
    }
  }

  Future<void> _updatePeers(LanChatService service) async {
    final peers = service.visiblePeers
        .map((peer) => '${peer.name} - ${peer.platformLabel} - ${peer.address.address}')
        .toList(growable: false);
    try {
      await _channel.invokeMethod<void>('updatePeers', peers);
    } catch (_) {
      return;
    }
  }
}

class WindowsStartupService {
  WindowsStartupService._();

  static final WindowsStartupService instance = WindowsStartupService._();

  static const String _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'WifiChatShare';
  static const String _startupFileName = 'WifiChatShare.cmd';

  Future<bool> setEnabled(bool value) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      if (value) {
        await _deleteLegacyRegistryStartup();
        final startupFile = await _startupFile();
        await startupFile.parent.create(recursive: true);
        final executable = Platform.resolvedExecutable;
        await startupFile.writeAsString(
          '@echo off\r\nstart "" "${_escapeCmdPath(executable)}"\r\n',
          flush: true,
        );
        return startupFile.existsSync();
      }

      final startupFile = await _startupFile();
      if (await startupFile.exists()) {
        await startupFile.delete();
      }
      await _deleteLegacyRegistryStartup();
      return !startupFile.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<File> _startupFile() async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      throw const FileSystemException('APPDATA is not available');
    }
    return File(
      '$appData${Platform.pathSeparator}Microsoft${Platform.pathSeparator}Windows'
      '${Platform.pathSeparator}Start Menu${Platform.pathSeparator}Programs'
      '${Platform.pathSeparator}Startup${Platform.pathSeparator}$_startupFileName',
    );
  }

  Future<void> _deleteLegacyRegistryStartup() async {
    try {
      await Process.run('reg.exe', [
        'delete',
        _runKey,
        '/v',
        _valueName,
        '/f',
      ]);
    } catch (_) {
      return;
    }
  }

  String _escapeCmdPath(String value) {
    return value.replaceAll('"', '""');
  }
}

class WindowsDesktopTools {
  WindowsDesktopTools._();

  static final WindowsDesktopTools instance = WindowsDesktopTools._();

  Future<void> runFirewallScript() async {
    if (!Platform.isWindows) {
      return;
    }
    final script = _scriptPath('Allow_WifiChatShare_Firewall.ps1');
    final command =
        'Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File ${_quoteForPowerShell(script)}"';
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> runPortTestScript() async {
    if (!Platform.isWindows) {
      return;
    }
    final script = _scriptPath('Test_WifiChatShare_Port.ps1');
    final command =
        'Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File ${_quoteForPowerShell(script)}"';
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      mode: ProcessStartMode.detached,
    );
  }

  String _scriptPath(String fileName) {
    return '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$fileName';
  }

  String _quoteForPowerShell(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

class AndroidQuickSettingsService {
  AndroidQuickSettingsService._();

  static final AndroidQuickSettingsService instance = AndroidQuickSettingsService._();

  static const MethodChannel _channel = MethodChannel('wifi_chat_share/android');

  Future<bool> requestTile() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('requestQuickSettingsTile') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;

  bool get isFresh => DateTime.now().difference(lastSeen) < const Duration(seconds: 30);

  String get platformLabel {
    switch (platform) {
      case 'windows':
        return 'Windows PC';
      case 'macos':
        return 'Mac';
      case 'linux':
        return 'Linux PC';
      case 'android':
        return 'Android phone';
      case 'ios':
        return 'iPhone';
      default:
        return 'Device';
    }
  }
}

enum MessageKind { text, file, folder, system }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerId,
    required this.text,
    required this.kind,
    required this.outgoing,
    required this.createdAt,
    this.fileName,
    this.filePath,
  });

  final String id;
  final String peerId;
  final String text;
  final MessageKind kind;
  final bool outgoing;
  final DateTime createdAt;
  final String? fileName;
  final String? filePath;
}

class IncomingEnvelope {
  const IncomingEnvelope({required this.header, required this.bodyFile});

  final Map<String, dynamic> header;
  final File? bodyFile;
}

IconData _platformIcon(String platform) {
  switch (platform) {
    case 'windows':
    case 'macos':
    case 'linux':
      return Icons.desktop_windows;
    case 'android':
      return Icons.android;
    case 'ios':
      return Icons.phone_iphone;
    default:
      return Icons.devices;
  }
}

String _platformName() {
  if (Platform.isWindows) {
    return 'windows';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isLinux) {
    return 'linux';
  }
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isIOS) {
    return 'ios';
  }
  return 'unknown';
}

String _localDeviceName() {
  try {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) {
      return host;
    }
  } catch (_) {
    return 'Wifi Chat Device';
  }
  return 'Wifi Chat Device';
}

Future<List<InternetAddress>> _localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return interfaces.expand((interface) => interface.addresses).where((address) {
      final value = address.address;
      return !value.startsWith('127.') && !value.startsWith('169.254.');
    }).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String _shortError(Object error) {
  final text = error.toString();
  if (text.length <= 140) {
    return text;
  }
  return '${text.substring(0, 137)}...';
}

String _makeId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _safeFileName(String name) {
  final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'received-file' : sanitized;
}

String _folderNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.trim().isNotEmpty).toList(growable: false);
  return parts.isEmpty ? 'folder' : parts.last;
}

String _relativeArchivePath(String basePath, String filePath) {
  final normalizedBase = basePath.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
  final normalizedFile = filePath.replaceAll('\\', '/');
  if (!normalizedFile.startsWith('$normalizedBase/')) {
    return _folderNameFromPath(filePath);
  }
  return normalizedFile.substring(normalizedBase.length + 1);
}

String? _safeArchiveEntryPath(String name) {
  final parts = name
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.trim().isNotEmpty && part != '.')
      .toList(growable: false);
  if (parts.isEmpty || parts.any((part) => part == '..')) {
    return null;
  }
  return parts.map(_safeFileName).join(Platform.pathSeparator);
}

String _copyTextForMessage(ChatMessage message) {
  if (message.kind == MessageKind.file || message.kind == MessageKind.folder) {
    final parts = <String>[
      if ((message.fileName ?? '').trim().isNotEmpty) message.fileName!.trim(),
      if ((message.filePath ?? '').trim().isNotEmpty) message.filePath!.trim(),
    ];
    return parts.join('\n');
  }
  return message.text;
}

String _timeLabel(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
