import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/assistant/reading_context.dart';
import 'package:hackathon_reading/features/companion/companion_chat.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomRight,
      child: SizedBox(width: 320, child: child),
    ),
  ),
);

void main() {
  testWidgets('lists the reader and the companion bubbles', (tester) async {
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读 · 第一部分',
          messages: const [
            ChatMessage(role: ChatRole.user, content: '这一页在讲什么？'),
            ChatMessage(role: ChatRole.assistant, content: '外婆在挑鞋，母亲在讲她小时候。'),
          ],
          streaming: '',
          busy: false,
          onSend: (_) {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('陪读 · 第一部分'), findsOneWidget);
    expect(find.text('这一页在讲什么？'), findsOneWidget);
    expect(find.text('外婆在挑鞋，母亲在讲她小时候。'), findsOneWidget);
  });

  testWidgets('sends what the reader typed', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读',
          messages: const [],
          streaming: '',
          busy: false,
          onSend: sent.add,
          onClose: () {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('companion-chat-input')),
      '她为什么生气？',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['她为什么生气？']);
  });

  testWidgets('shows the streaming tail and blocks sending while busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读',
          messages: const [],
          streaming: '外婆正',
          busy: true,
          onSend: (_) {},
          onClose: () {},
        ),
      ),
    );

    expect(find.textContaining('外婆正'), findsOneWidget);
    final send = tester.widget<IconButton>(
      find.byKey(const Key('companion-chat-send')),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('closing hands control back to the reader', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读',
          messages: const [],
          streaming: '',
          busy: false,
          onSend: (_) {},
          onClose: () => closed++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('companion-chat-close')));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('offers the skin picker only when the host can swap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读',
          messages: const [],
          streaming: '',
          busy: false,
          onSend: (_) {},
          onClose: () {},
        ),
      ),
    );
    expect(find.byKey(const Key('companion-skin-open')), findsNothing);

    var opened = 0;
    await tester.pumpWidget(
      _host(
        CompanionChatPanel(
          title: '陪读',
          messages: const [],
          streaming: '',
          busy: false,
          onSend: (_) {},
          onClose: () {},
          onChangeSkin: () => opened++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('companion-skin-open')));
    await tester.pump();
    expect(opened, 1);
  });
}
