# Mobile MCP (Model Context Protocol)

Mobile MCP is a Flutter implementation of the Model Context Protocol designed specifically for cross-app tool discovery and execution on iOS and Android.

It allows "Host" applications (like AI assistants or LLM-powered chats) to discover and securely use "Tools" provided by other applications installed on the same device.

## Features

- **Decentralized Tool Discovery**: No central server; tools are discovered directly between apps using deep links.
- **Secure Communication**: Local WebSocket connection with mandatory token-based authentication.
- **User Consent**: Built-in flow for Tool apps to request user permission before allowing a Host to connect.
- **Identity Verification**: On Android and iOS, the protocol now automatically verifies the calling app's package name/bundle ID during the handshake.
- **Secure Storage**: Includes `SecureMcpStorage` using platform-native encrypted storage (KeyChain/Keystore) for session tokens.
- **Background Execution**: Automatically manages background task locks on iOS and Android to ensure long-running tool calls complete successfully.
- **Standard JSON-RPC**: Uses the MCP standard (built on JSON-RPC 2.0) for tool listing and execution.

## Architecture

Mobile MCP uses a hybrid transport model to overcome mobile OS limitations:

1.  **Handshake (Deep Links)**: The Host and Tool apps exchange connection details (WebSocket port, session token) using platform-standard deep links.
2.  **Session (WebSockets)**: Once the handshake is complete, the apps communicate over a local WebSocket server running on the Tool app.

## Getting Started

Add `mobile_mcp` to your `pubspec.yaml`:

```yaml
dependencies:
  mobile_mcp: ^1.0.0
```

### Platform Setup

Mobile MCP uses a hybrid transport. For maximum security, it is **highly recommended** to use **App Links (Android)** and **Universal Links (iOS)** instead of custom URL schemes whenever possible.

#### Custom URL Schemes (Basic)

Both Host and Tool apps must configure custom URL schemes in their respective platform files.

#### Android (`AndroidManifest.xml`)

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="your-app-scheme" android:host="mcp" />
</intent-filter>
```

#### iOS (`Info.plist`)

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>your-app-scheme</string>
        </array>
    </dict>
</array>
```

---

## Usage: Tool Perspective

A "Tool" app provides capabilities to other apps.

### 1. Initialize `McpTool`

For production apps, always use `SecureMcpStorage` (default) and enable `strictTransport` to protect against deep link hijacking:

```dart
final mcpTool = McpTool(
  appScheme: 'my-tool-app',
  // strictTransport: true, // Only allow HTTPS (App/Universal Links)
  // trustedHostPackages: ['com.example.ai_host'], // Optional whitelist
  logLevel: McpLogLevel.info,
);
```

### 2. Register Tools

Define the tools your app provides:

```dart
mcpTool.registerTool(
  definition: const McpToolDefinition(
    name: 'fetch_notes',
    description: 'Fetches user notes with an optional limit',
    inputSchema: {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer'}
      }
    },
  ),
  handler: (args) async {
    final limit = args['limit'] ?? 10;
    return [{'id': 1, 'text': 'Hello World'}];
  },
);
```

### 3. Handle User Consent

You must provide a way for users to approve connection requests from Host apps. It is **critical** to show a security warning and verify the caller's identity:

```dart
mcpTool.setConsentHandler((hostInfo) async {
  // hostInfo.isVerified indicates if the OS successfully
  // identified the calling app (package name/bundle ID).

  // Show a dialog to the user with a security warning
  bool allowed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Connection Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${hostInfo.name} (${hostInfo.callingPackage ?? "Unknown App"}) wants to connect.'),
          SizedBox(height: 16),
          Text(
            'WARNING: Only allow connections from apps you trust. '
            'This app will be able to execute tools and access data.',
            style: TextStyle(color: Colors.red),
          ),
        ],
      ),
      actions: [ ... ],
    ),
  );
  return allowed ?? false;
});
```

**Note**: Once a Host is approved, subsequent connection attempts using the same pairing token are automatically accepted without re-prompting the user.

### 4. Initialize and Register with Host

```dart
await mcpTool.initialize();

// Optionally, trigger registration with a known Host
mcpTool.registerWithHost('ai-host-app');
```

---

## Usage: Host Perspective

A "Host" app uses tools provided by other apps.

### 1. Initialize `McpHost`

```dart
final mcpHost = McpHost(
  hostScheme: 'ai-host-app',
  hostName: 'My AI Assistant',
);

await mcpHost.initialize();
```

### 2. Discover Tools

Listen for new tools being registered:

```dart
mcpHost.onToolRegistered.listen((entry) {
  print('New tool app discovered: ${entry.displayName}');
});
```

### 3. Execute a Tool Call

```dart
try {
  final result = await mcpHost.executeTool(
    'my-tool-app',      // The scheme of the tool app
    'fetch_notes',      // The name of the tool
    {'limit': 5},       // Arguments
  );
  print('Tool result: $result');
} catch (e) {
  print('Error executing tool: $e');
}
```

## Security Best Practices

Mobile MCP provides several layers of protection, but must be configured correctly for production:

### 1. Use App Links and Universal Links
Enable `strictTransport: true` in both `McpHost` and `McpTool`. This ensures that all handshake deep links use `https://` URIs, which are verified by the mobile OS. Custom URL schemes (like `my-app://`) are insecure and susceptible to hijacking.

### 2. Verify Caller Identity
In your `McpTool`'s `consentHandler`, check `hostInfo.isVerified` and `hostInfo.isUniversalLink`. For maximum security, provide a `trustedHostPackages` whitelist to `McpTool` to only allow connections from known, verified package names.

### 3. Use Secure Storage (Default)
Mobile MCP now uses `SecureMcpStorage` by default, which utilizes the platform's secure enclave (KeyChain on iOS, Keystore on Android). Do not override this with `DefaultMcpStorage` in production.

### 4. Provide Clear User Warnings
Always display a clear consent dialog that identifies the requesting app and explains the risks of sharing data with AI applications.

## Troubleshooting

- **Deep Link Failures**: Ensure both apps have their URL schemes correctly registered in `AndroidManifest.xml` and `Info.plist`.
- **Connection Closed**: The Tool app might have been terminated by the OS. `McpHost` automatically attempts to "wake up" the Tool app via deep link if a connection is lost, but some OS-level background restrictions may still apply.
- **Bad State: Stream has already been listened to**: This usually indicates an internal error in how the WebSocket is handled. Ensure you are using the latest version of the package where this has been fixed.
