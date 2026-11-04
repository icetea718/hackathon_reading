import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/tts/edge/edge_token.dart';

/// The three vectors below were produced by the vendored reference
/// implementation (`MsEdgeTTS.generateSecMsGec` in chino-tts'
/// `vendor/msedge-tts`), so they pin the port to the real algorithm: any drift
/// in the word swap, the reversible chain or the 5-minute rounding shows up as
/// a mismatch instead of as a handshake rejection at runtime.
void main() {
  String tokenAt(int millis) => EdgeToken.generate(
        now: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      );

  test('matches the reference token for a fixed clock', () {
    expect(
      tokenAt(1700000000000),
      '2CD23A2CA0B2595A-'
      'F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2',
    );
  });

  test('matches the reference token for a later clock', () {
    expect(
      tokenAt(1750000000000),
      'B029A7426816F097-'
      '4579D112DC47FC3BF432B499C0A282F427C659474AF9BF5FA33CE2C003F9E9C2',
    );
  });

  test('matches the reference token for the v2 rollout date', () {
    expect(
      tokenAt(1762252800000),
      '6B94D7B51B532388-'
      'BE8A54098ACF2B9D7D2E3E2471E307E5A85FC93C14B4B245A6B90FBF8A057521',
    );
  });

  test('rounds the clock to the five minute window', () {
    // Two instants in the same 300 s window share a token, one just outside it
    // does not: that is what keeps the value stable while a clip is playing.
    final start = DateTime.fromMillisecondsSinceEpoch(1762252800000, isUtc: true);
    final sameWindow = start.add(const Duration(seconds: 120));
    final nextWindow = start.add(const Duration(seconds: 400));
    expect(
      EdgeToken.generate(now: sameWindow),
      EdgeToken.generate(now: start),
    );
    expect(
      EdgeToken.generate(now: nextWindow),
      isNot(EdgeToken.generate(now: start)),
    );
  });

  test('keeps the documented shape', () {
    final token = EdgeToken.generate();
    expect(
      RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$').hasMatch(token),
      isTrue,
      reason: token,
    );
  });
}
