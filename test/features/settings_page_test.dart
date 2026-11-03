import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/app/providers.dart';
import 'package:hackathon_reading/data/db/app_database.dart';
import 'package:hackathon_reading/data/repositories/settings_repository.dart';
import 'package:hackathon_reading/distill/llm/llm_client.dart';
import 'package:hackathon_reading/distill/llm/llm_config.dart';
import 'package:hackathon_reading/features/settings/settings_page.dart';

class _FakeClient implements LlmClient {
  _FakeClient({this.failWith});

  final String? failWith;
  int calls = 0;

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    calls++;
    if (failWith != null) throw LlmException(failWith!);
    return 'pong';
  }

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    yield 'pong';
  }

  @override
  void dispose() {}
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpPage(WidgetTester tester, LlmClient client) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llmClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tests the connection and saves the typed values', (tester) async {
    final fake = _FakeClient();
    await pumpPage(tester, fake);

    await tester.enterText(find.byKey(const Key('llm-api-key')), 'sk-test');
    await tester.enterText(find.byKey(const Key('llm-model')), 'custom-model');
    await tester.enterText(
      find.byKey(const Key('llm-base-url')),
      'http://localhost:8080/v1',
    );

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.text('连接成功'), findsOneWidget);
    expect(fake.calls, 1);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await LlmConfigStore(SettingsRepository(db)).load();
    expect(saved.apiKey, 'sk-test');
    expect(saved.model, 'custom-model');
    expect(saved.baseUrl, 'http://localhost:8080/v1');
  });

  testWidgets('reports a failed connection attempt', (tester) async {
    await pumpPage(tester, _FakeClient(failWith: 'HTTP 401: bad key'));

    await tester.enterText(find.byKey(const Key('llm-api-key')), 'sk-bad');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('连接失败'), findsOneWidget);
  });

  testWidgets('loads previously stored settings into the form', (tester) async {
    await LlmConfigStore(SettingsRepository(db)).save(
      const LlmConfig(
        baseUrl: 'https://example.test/v1',
        model: 'stored-model',
        apiKey: 'sk-stored',
      ),
    );

    await pumpPage(tester, _FakeClient());

    expect(find.text('https://example.test/v1'), findsOneWidget);
    expect(find.text('stored-model'), findsOneWidget);
  });
}
