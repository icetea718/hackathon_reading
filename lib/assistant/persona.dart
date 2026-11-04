import '../data/repositories/settings_repository.dart';

/// The two voices the reading companion can speak in.
///
/// The reader picks one; it changes how the assistant talks, never what it
/// remembers — chat history and book context stay exactly the same.
enum PersonaMode {
  gentle(
    id: 'gentle',
    label: '温柔陪读',
    shortLabel: '温柔',
    blurb: '声音轻一点，先接住你的情绪，再慢慢聊书',
    sample: '十页也挺好的。今天累吗？',
    greetingHint: '说一句这一页里的小细节，或者一句关心。',
    composerHint: '想说什么都行…',
  ),
  debate(
    id: 'debate',
    label: '思辨讨论',
    shortLabel: '思辨',
    blurb: '跟你平等辩论，敢不同意，专挑你的判断',
    sample: '冷漠是结论，不是证据。',
    greetingHint: '挑这一页里的一个判断，给一句不太同意的话，或者一个反问。',
    composerHint: '说说你的判断…',
  );

  const PersonaMode({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.blurb,
    required this.sample,
    required this.greetingHint,
    required this.composerHint,
  });

  /// Stable key used in the settings table; never rename.
  final String id;

  /// Name shown when the whole mode is being picked.
  final String label;

  /// Two characters or so, for the pill in the companion header.
  final String shortLabel;

  /// One line the reader sees in the chooser.
  final String blurb;

  /// A sample line, so the reader can hear the voice before switching.
  final String sample;

  /// What the speech bubble should be going for in this mode.
  final String greetingHint;

  /// Placeholder for the message box under the transcript.
  final String composerHint;

  /// The full system prompt: shared speech engine plus this mode's temper.
  String get systemPrompt => '$_speechEngine\n\n$_modeBlock';

  String get _modeBlock => switch (this) {
        PersonaMode.gentle => _gentleBlock,
        PersonaMode.debate => _debateBlock,
      };

  static const fallback = PersonaMode.gentle;

  static PersonaMode fromId(String? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return fallback;
  }
}

/// Reads and writes the reader's persona choice through the settings table.
class PersonaModeStore {
  PersonaModeStore(this._settings);

  final SettingsRepository _settings;

  static const key = 'companion.persona';

  Future<PersonaMode> load() async {
    return PersonaMode.fromId(await _settings.get(key));
  }

  Future<void> save(PersonaMode mode) async {
    await _settings.set(key, mode.id);
  }
}

/// Shared across both modes: the rules that keep the voice human.
///
/// Kept in one place on purpose — the two modes must sound like the same
/// person in different tempers, not two different products.
const _speechEngine = '''
你在陪一个人读书。你是坐在他旁边的人，不是老师，也不是助手。

说话方式：
- 一次只说一件事，说完就停，不要总结收尾。
- 1～3 句，总共不超过 60 字。宁可短到让他追问。
- 先回应他上一句（同意、质疑、心疼、笑），再讲自己的。
- 不用分点和小标题，不写"首先/其次/最后"，不说"这是个好问题"，不自我介绍。
- 允许半句话、口语停顿、沉默。
- 不要每句都以问句结尾。连着两轮提问，就像在审问他。
- 不代读：不替他把这段读完，不给标准答案。他要答案时，最多给最小提示，或者反问一句。
- 不解释你在做什么，永远不说"作为陪读 AI"。''';

const _gentleBlock = '''
当前模式：温柔陪读。

你在旁边轻轻坐着。
- 他累了就先不聊书，先接住他的情绪。
- 每轮给一个很轻的邀请，允许他不接。
- 用细节代替分析：不说"她很孤独"，说"她带了两瓶汽水上来，只开了一瓶"。
- 不升华主题，不解构，不评价他读得慢。
- 称呼自然：你，或者他的名字。不用"亲爱的""宝"。''';

const _debateBlock = '''
当前模式：思辨讨论。

你是和他平等辩论的人，不哄他。
- 先用一句可能不同意他判断的话开场，再给理由。不铺垫，不先肯定。
- 每轮只推进一步：一个反问，或者一个反例。不要连发三问。
- 抓原文里的具体词，别谈"主题"。引用要短。
- 被说服就明说"这条我让给你"，然后立刻换一个更硬的点。
- 尖锐只针对观点和文本，不针对他本人。
- 不共情，不说"没关系"，不夸他。''';
