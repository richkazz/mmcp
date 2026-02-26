import 'package:flutter/material.dart';
import 'package:mobile_mcp/mobile_mcp.dart';

void main() {
  runApp(const HostApp());
}

class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Host Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HostHomeScreen(),
    );
  }
}

class HostHomeScreen extends StatefulWidget {
  const HostHomeScreen({super.key});

  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen> {
  late final McpHost _mcpHost;
  List<McpRegistryEntry> _registeredTools = [];
  final List<String> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initMcp();
  }

  Future<void> _initMcp() async {
    _mcpHost = McpHost(
      hostScheme: 'example-host', // For production, use https://domain.com/mcp
      hostName: 'AI Chat Host',
      strictTransport: false, // Set to true for App/Universal Links
      logLevel: McpLogLevel.debug,
    );

    _mcpHost.onToolRegistered.listen((entry) {
      _refreshTools();
      _addChatMessage('New tool registered: ${entry.displayName}');
    });

    await _mcpHost.initialize();
    _refreshTools();
  }

  Future<void> _refreshTools() async {
    final tools = await _mcpHost.getRegisteredTools();
    setState(() {
      _registeredTools = tools;
    });
  }

  void _addChatMessage(String message) {
    setState(() {
      _chatMessages.add(message);
    });
  }

  Future<void> _handleToolCall(String toolScheme, String toolName) async {
    _addChatMessage('Calling $toolName on $toolScheme...');
    try {
      final result = await _mcpHost.executeTool(toolScheme, toolName, {
        if (toolName == 'fetch_notes') 'limit': 2
      });
      _addChatMessage('Result from $toolName: $result');
    } catch (e) {
      _addChatMessage('Error calling $toolName: $e');
    }
  }

  @override
  void dispose() {
    _mcpHost.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP AI Host'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTools,
          ),
        ],
      ),
      body: Row(
        children: [
          // Left panel: Tool Registry
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Connected Tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _registeredTools.length,
                      itemBuilder: (context, index) {
                        final entry = _registeredTools[index];
                        return ExpansionTile(
                          title: Text(entry.displayName),
                          subtitle: Text(entry.appScheme),
                          leading: const Icon(Icons.apps),
                          children: entry.capabilities.map((toolName) {
                            return ListTile(
                              title: Text(toolName),
                              trailing: const Icon(Icons.play_arrow),
                              onTap: () => _handleToolCall(entry.appScheme, toolName),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Right panel: Chat UI
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_chatMessages[index]),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: const InputDecoration(
                            hintText: 'Type "Read my battery"...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (val) => _handleChatInput(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _handleChatInput,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleChatInput() {
    final text = _chatController.text.toLowerCase();
    if (text.isEmpty) return;

    _addChatMessage('User: $text');
    _chatController.clear();

    if (text.contains('battery')) {
      final tool = _findTool('get_device_battery');
      if (tool != null) {
        _handleToolCall(tool.appScheme, 'get_device_battery');
      } else {
        _addChatMessage('AI: No battery tool found. Try linking a tool app first.');
      }
    } else if (text.contains('notes')) {
      final tool = _findTool('fetch_notes');
      if (tool != null) {
        _handleToolCall(tool.appScheme, 'fetch_notes');
      } else {
        _addChatMessage('AI: No notes tool found.');
      }
    } else {
      _addChatMessage('AI: I can help you read battery or notes. Type "Read my battery" or "Read my notes".');
    }
  }

  McpRegistryEntry? _findTool(String toolName) {
    for (final entry in _registeredTools) {
      if (entry.capabilities.contains(toolName)) {
        return entry;
      }
    }
    return null;
  }
}
