import 'package:hackathon_reading/distill/llm/llm_client.dart';

/// Records every request and replays a canned answer.
class FakeLlmClient implements LlmClient {
  FakeLlmClient({this.reply = 'ok', this.jsonReply = '{}'});

  String reply;
  String jsonReply;

  final List<List<LlmMessage>> calls = [];
  final List<bool> streamed = [];
  final List<double?> temperatures = [];
  bool disposed = false;

  List<LlmMessage> get lastMessages => calls.last;

  @override
  Stream<String> streamChat(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async* {
    calls.add(messages);
    streamed.add(true);
    temperatures.add(temperature);
    yield reply;
  }

  @override
  Future<String> completeJson(
    List<LlmMessage> messages, {
    double? temperature,
    int? maxTokens,
    CancelToken? cancel,
  }) async {
    calls.add(messages);
    streamed.add(false);
    temperatures.add(temperature);
    return jsonReply;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
