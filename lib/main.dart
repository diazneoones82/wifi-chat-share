import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int discoveryPort = 45872;
const int transferPort = 45873;

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
  bool darkMode = false;
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
      darkMode = prefs.getBool('darkMode') ?? false;
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      startAtStartup = prefs.getBool('startAtStartup') ?? false;
      downloadDirectory = prefs.getString('downloadDirectory');
    });
    await NotificationService.instance.setEnabled(notificationsEnabled);
    if (Platform.isWindows && startAtStartup) {
      await WindowsStartupService.instance.setEnabled(true);
    }
  }

  Future<void> _setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
    setState(() => darkMode = value);
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wifi Chat Share',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f766e)),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff14b8a6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: HomeScreen(
        darkMode: darkMode,
        downloadDirectory: downloadDirectory,
        notificationsEnabled: notificationsEnabled,
        startAtStartup: startAtStartup,
        onDarkModeChanged: _setDarkMode,
        onDownloadDirectoryChanged: _setDownloadDirectory,
        onNotificationsChanged: _setNotificationsEnabled,
        onStartAtStartupChanged: _setStartAtStartup,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.darkMode,
    required this.downloadDirectory,
    required this.notificationsEnabled,
    required this.startAtStartup,
    required this.onDarkModeChanged,
    required this.onDownloadDirectoryChanged,
    required this.onNotificationsChanged,
    required this.onStartAtStartupChanged,
    super.key,
  });

  final bool darkMode;
  final String? downloadDirectory;
  final bool notificationsEnabled;
  final bool startAtStartup;
  final ValueChanged<bool> onDarkModeChanged;
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
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 760;
              if (isCompact) {
                return Column(
                  children: [
                    StatusBar(text: service.lastStatus),
                    Expanded(
                      child: selectedPeer == null
                          ? PeerList(
                              peers: peers,
                              selectedPeerId: selectedPeerId,
                              onSelect: (peer) => setState(() => selectedPeerId = peer.id),
                            )
                          : ChatPane(
                              service: service,
                              peer: selectedPeer,
                              controller: messageController,
                              onBack: () => setState(() => selectedPeerId = null),
                            ),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  StatusBar(text: service.lastStatus),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 330,
                          child: PeerList(
                            peers: peers,
                            selectedPeerId: selectedPeerId,
                            onSelect: (peer) => setState(() => selectedPeerId = peer.id),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: selectedPeer == null
                              ? EmptyState(
                                  isRunning: service.isRunning,
                                  deviceName: service.localName,
                                )
                              : ChatPane(
                                  service: service,
                                  peer: selectedPeer,
                                  controller: messageController,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        darkMode: widget.darkMode,
        downloadDirectory: widget.downloadDirectory,
        notificationsEnabled: widget.notificationsEnabled,
        startAtStartup: widget.startAtStartup,
        onDarkModeChanged: widget.onDarkModeChanged,
        onDownloadDirectoryChanged: widget.onDownloadDirectoryChanged,
        onNotificationsChanged: widget.onNotificationsChanged,
        onStartAtStartupChanged: widget.onStartAtStartupChanged,
      ),
    );
  }
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    required this.darkMode,
    required this.downloadDirectory,
    required this.notificationsEnabled,
    required this.startAtStartup,
    required this.onDarkModeChanged,
    required this.onDownloadDirectoryChanged,
    required this.onNotificationsChanged,
    required this.onStartAtStartupChanged,
    super.key,
  });

  final bool darkMode;
  final String? downloadDirectory;
  final bool notificationsEnabled;
  final bool startAtStartup;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<String?> onDownloadDirectoryChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onStartAtStartupChanged;

  @override
  Widget build(BuildContext context) {
    final effectivePath = downloadDirectory ?? 'Documents / app documents';
    return AlertDialog(
      title: const Text('Settings'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dark mode'),
              value: darkMode,
              onChanged: onDarkModeChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifications'),
              subtitle: const Text('Show popups for incoming chats and files'),
              value: notificationsEnabled,
              onChanged: onNotificationsChanged,
            ),
            if (Platform.isWindows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start with Windows'),
                subtitle: const Text('Open Wifi Chat Share when you sign in'),
                value: startAtStartup,
                onChanged: onStartAtStartupChanged,
              ),
            if (Platform.isAndroid)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flash_on_outlined),
                title: const Text('Android Quick Settings tile'),
                subtitle: const Text('Add a tile to open or close the app'),
                trailing: FilledButton(
                  onPressed: AndroidQuickSettingsService.instance.requestTile,
                  child: const Text('Add'),
                ),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Received files location'),
              subtitle: Text(
                effectivePath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onDownloadDirectoryChanged(null),
                  child: const Text('Use default'),
                ),
                const SizedBox(width: 8),
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
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class StatusBar extends StatelessWidget {
  const StatusBar({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class PeerList extends StatelessWidget {
  const PeerList({
    required this.peers,
    required this.selectedPeerId,
    required this.onSelect,
    super.key,
  });

  final List<PeerDevice> peers;
  final String? selectedPeerId;
  final ValueChanged<PeerDevice> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Nearby devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        leading: CircleAvatar(
                          child: Icon(_platformIcon(peer.platform)),
                        ),
                        title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${peer.platformLabel} • ${peer.address.address}'),
                        trailing: Icon(peer.isFresh ? Icons.circle : Icons.schedule, size: 14),
                        onTap: () => onSelect(peer),
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
}

class ChatPane extends StatelessWidget {
  const ChatPane({
    required this.service,
    required this.peer,
    required this.controller,
    this.onBack,
    super.key,
  });

  final LanChatService service;
  final PeerDevice peer;
  final TextEditingController controller;
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
              trailing: IconButton(
                tooltip: 'Send file',
                icon: const Icon(Icons.attach_file),
                onPressed: () => service.pickAndSendFile(peer),
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
                  tooltip: 'Attach file',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: () => service.pickAndSendFile(peer),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
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
              if (message.kind == MessageKind.file)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.fileName ?? 'File',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              else
                Text(message.text, style: TextStyle(color: foreground)),
              if (message.kind == MessageKind.file && message.filePath != null) ...[
                const SizedBox(height: 6),
                Text(
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

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.isRunning,
    required this.deviceName,
    super.key,
  });

  final bool isRunning;
  final String deviceName;

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
  String? _downloadDirectory;
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

  List<PeerDevice> get visiblePeers {
    final values = peers.values.toList()
      ..sort((a, b) {
        final fresh = b.lastSeen.compareTo(a.lastSeen);
        return fresh == 0 ? a.name.compareTo(b.name) : fresh;
      });
    return values;
  }

  Future<void> start() async {
    if (isRunning) {
      return;
    }

    await _requestPermissions();
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
    if (_udpSocket != null && _server != null && isRunning) {
      broadcastNow();
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
      lastStatus = 'Discovery broadcast sent';
    } catch (error) {
      socket.close();
      _udpSocket = null;
      lastStatus = 'Discovery send failed; reconnecting: ${_shortError(error)}';
    }
    notifyListeners();
  }

  List<ChatMessage> messagesFor(String peerId) => List.unmodifiable(_messages[peerId] ?? const []);

  void setDownloadDirectory(String? path) {
    _downloadDirectory = path;
    lastStatus = path == null ? 'Received files will save to Documents' : 'Received files will save to $path';
    notifyListeners();
  }

  Future<void> refreshNow() async {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 45));
    peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));

    if (_server == null) {
      await _bindTransferServer();
    }
    if (_udpSocket == null) {
      await _bindDiscoverySocket();
    }
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

  Future<void> _sendEnvelope(PeerDevice peer, Map<String, Object?> header, [Uint8List? body]) async {
    final socket = await Socket.connect(peer.address, peer.port, timeout: const Duration(seconds: 8));
    try {
      final headerBytes = utf8.encode('${jsonEncode(header)}\n');
      socket.add(headerBytes);
      if (body != null) {
        socket.add(body);
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
      peers[id] = PeerDevice(
        id: id,
        name: (payload['name'] as String?)?.trim().isNotEmpty == true ? payload['name'] as String : 'Unknown device',
        platform: payload['platform'] as String? ?? 'unknown',
        address: datagram.address,
        port: payload['port'] as int? ?? transferPort,
        lastSeen: DateTime.now(),
      );
      lastStatus = 'Found ${peers[id]?.name} at ${datagram.address.address}';
      notifyListeners();
    } catch (_) {
      return;
    }
  }

  Future<void> _handleIncomingSocket(Socket socket) async {
    try {
      final bytes = await _collectBytes(socket);
      final split = bytes.indexOf(10);
      if (split <= 0) {
        return;
      }

      final header = jsonDecode(utf8.decode(bytes.sublist(0, split))) as Map<String, dynamic>;
      final body = bytes.sublist(split + 1);
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
        final incomingDir = await _incomingDirectory();
        if (!await incomingDir.exists()) {
          await incomingDir.create(recursive: true);
        }
        final file = File('${incomingDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}-$fileName');
        await file.writeAsBytes(body);

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

      notifyListeners();
    } catch (error) {
      lastStatus = 'Ignored dropped connection: ${_shortError(error)}';
      notifyListeners();
    } finally {
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

  Future<Uint8List> _collectBytes(Socket socket) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in socket) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _removeStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
    notifyListeners();
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
          appUserModelId: 'com.example.wifi_chat_share',
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

  Future<bool> setEnabled(bool value) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      if (value) {
        final executable = Platform.resolvedExecutable;
        final result = await Process.run('reg', [
          'add',
          _runKey,
          '/v',
          _valueName,
          '/t',
          'REG_SZ',
          '/d',
          '"$executable"',
          '/f',
        ]);
        return result.exitCode == 0;
      }

      final result = await Process.run('reg', [
        'delete',
        _runKey,
        '/v',
        _valueName,
        '/f',
      ]);
      return result.exitCode == 0 || result.exitCode == 1;
    } catch (_) {
      return false;
    }
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

enum MessageKind { text, file, system }

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

String _timeLabel(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
