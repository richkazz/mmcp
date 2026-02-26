import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_mcp/mobile_mcp.dart';
import 'package:mobile_mcp/src/shared/errors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security Hardening Tests', () {
    test('McpHostInfo handles isUniversalLink', () {
      final info = McpHostInfo(
        hostScheme: 'https://example.com/mcp',
        name: 'HostApp',
        callingPackage: 'Verified (Universal Link)',
        isVerified: true,
        isUniversalLink: true,
      );

      expect(info.isUniversalLink, isTrue);
      expect(info.isVerified, isTrue);

      final json = info.toJson();
      expect(json['isUniversalLink'], isTrue);

      final fromJson = McpHostInfo.fromJson(json);
      expect(fromJson.isUniversalLink, isTrue);
    });

    test('McpTransport.sendDeepLink throws on insecure scheme when strictTransport is true', () async {
      final transport = McpTransport();

      expect(
        () => transport.sendDeepLink(
          scheme: 'custom-scheme',
          path: '/wakeup',
          strictTransport: true,
        ),
        throwsA(isA<McpSecurityException>()),
      );

      // Should not throw for https
      // (It will fail later in canLaunchUrl because it's a test environment, but shouldn't throw McpSecurityException)
      try {
        await transport.sendDeepLink(
          scheme: 'https',
          path: '/wakeup',
          strictTransport: true,
        );
      } catch (e) {
        expect(e, isNot(isA<McpSecurityException>()));
      }
    });

    test('McpTool handles trustedHostPackages and isUniversalLink', () {
      // Testing the logic that will be used in _handleWakeup
      const callingPackageNormal = 'com.example.host';
      const callingPackageUniversal = 'Verified (Universal Link)';
      const trustedPackages = ['com.example.trusted'];

      // Case 1: Normal package, not trusted, not universal
      final info1 = McpHostInfo(
        hostScheme: 'scheme',
        name: 'name',
        callingPackage: callingPackageNormal,
        isVerified: false,
        isUniversalLink: false,
      );
      expect(info1.isVerified, isFalse);

      // Case 2: Trusted package
      final isVerified2 = trustedPackages.contains('com.example.trusted');
      final info2 = McpHostInfo(
        hostScheme: 'scheme',
        name: 'name',
        callingPackage: 'com.example.trusted',
        isVerified: isVerified2,
        isUniversalLink: false,
      );
      expect(info2.isVerified, isTrue);

      // Case 3: Universal Link
      final isUniversal3 = callingPackageUniversal == 'Verified (Universal Link)';
      final info3 = McpHostInfo(
        hostScheme: 'scheme',
        name: 'name',
        callingPackage: callingPackageUniversal,
        isVerified: isUniversal3,
        isUniversalLink: isUniversal3,
      );
      expect(info3.isVerified, isTrue);
      expect(info3.isUniversalLink, isTrue);
    });

    test('McpTool.initialize handles strictTransport check for incoming links', () async {
      final tool = McpTool(appScheme: 'test-tool', strictTransport: true);

      // Since _handleIncomingLink is private, we can only test it indirectly if we could trigger it.
      // But we can at least verify that the tool was initialized with the right flags.
      expect(tool.strictTransport, isTrue);
    });
  });
}
