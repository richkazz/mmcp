import 'package:flutter/material.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  runApp(const ToolApp());
}

class ToolApp extends StatelessWidget {
  const ToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Tool Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ToolHomeScreen(),
    );
  }
}

class ToolHomeScreen extends StatefulWidget {
  const ToolHomeScreen({super.key});

  @override
  State<ToolHomeScreen> createState() => _ToolHomeScreenState();
}

class _ToolHomeScreenState extends State<ToolHomeScreen> {
  late final McpTool _mcpTool;
  McpToolServerState _serverState = McpToolServerState.stopped;

  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initMcp();
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}: $message');
    });
  }

  Future<void> _initMcp() async {
    _mcpTool = McpTool(
      appScheme: 'example-tool', // For production, use https://domain.com/mcp
      strictTransport: false, // Set to true for App/Universal Links
      // trustedHostPackages: ['com.example.ai_host'], // Optional whitelist
      logLevel: McpLogLevel.debug,
    );

    // Register Tools
    _mcpTool.registerTool(
      definition: const McpToolDefinition(
        name: 'get_device_battery',
        description: 'Returns the current battery level of the device',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      handler: (args) async {
        _addLog('Executing get_device_battery');
        return {'level': 85, 'status': 'charging'};
      },
    );

    _mcpTool.registerTool(
      definition: const McpToolDefinition(
        name: 'fetch_notes',
        description: 'Fetches user notes with an optional limit',
        inputSchema: {
          'type': 'object',
          'properties': {
            'limit': {'type': 'integer', 'description': 'Max notes to return'}
          }
        },
      ),
      handler: (args) async {
        final limit = args['limit'] as int? ?? 10;
        _addLog('Executing fetch_notes (limit: $limit)');
        return [
          {'id': 1, 'text': 'Buy milk'},
          {'id': 2, 'text': 'Finish MCP implementation'},
        ].take(limit).toList();
      },
    );

    // Set Consent Handler
    _mcpTool.setConsentHandler((hostInfo) async {
      _addLog('Consent requested by ${hostInfo.name}');
      final bool? allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connection Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${hostInfo.name} wants to connect to your tools.'),
              const SizedBox(height: 8),
              Text(
                'Source: ${hostInfo.callingPackage ?? "Unknown App"}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: hostInfo.isVerified ? Colors.green : Colors.orange,
                ),
              ),
              if (hostInfo.isUniversalLink)
                const Text(
                  'Verified Transport: Universal/App Link',
                  style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 16),
              const Text(
                'SECURITY WARNING:',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Allowing this connection gives the AI host access to execute tools in this app. '
                'Only allow connections from apps you trust.',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Deny'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      final result = allowed ?? false;
      _addLog('Consent ${result ? 'granted' : 'denied'}');
      return result;
    });

    // Listen to state changes
    _mcpTool.stateChanges.listen((state) {
      setState(() {
        _serverState = state;
      });
      _addLog('Server state: ${state.name}');
    });

    await _mcpTool.initialize();
    _addLog('McpTool initialized');
  }

  @override
  void dispose() {
    _mcpTool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Tool App'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            const Text(
              'Registered Tools:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: _mcpTool.registeredTools.length,
                itemBuilder: (context, index) {
                  final tool = _mcpTool.registeredTools[index];
                  return ListTile(
                    title: Text(tool.name),
                    subtitle: Text(tool.description),
                    leading: const Icon(Icons.build),
                  );
                },
              ),
            ),
            const Divider(),
            const Text(
              'Logs:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black87,
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(
                    _logs[index],
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _mcpTool.registerWithHost('example-host'),
              icon: const Icon(Icons.link),
              label: const Text('Link to AI Host'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor;
    IconData statusIcon;

    switch (_serverState) {
      case McpToolServerState.stopped:
        statusColor = Colors.grey;
        statusIcon = Icons.stop_circle;
      case McpToolServerState.listening:
        statusColor = Colors.orange;
        statusIcon = Icons.radio_button_checked;
      case McpToolServerState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
    }

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 48),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Server Status', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_serverState.name.toUpperCase(),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
