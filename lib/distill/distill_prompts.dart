import 'dart:convert';

import '../distill/llm/llm_client.dart';
import 'distill_models.dart';
import 'distill_planner.dart';

/// Shared system prompt: every distill call is a strict JSON editing job.
const distillSystemPrompt = '''
你是中文书籍蒸馏编辑，为「陪读者读书」的助手准备背景资料。
规则：
1. 只依据用户给出的原文，不引入外部知识，不编造人物、情节或引文。
2. 输出必须是合法 JSON，不要 Markdown 代码围栏，不要在 JSON 前后写任何解释。
3. 引用必须逐字摘自原文，单条不超过 150 字；没有合适的原句就省略该字段。
4. 一律使用简体中文。
''';

List<LlmMessage> mapPrompt(
  DistillSegment segment, {
  required String bookTitle,
  String? previousGist,
}) {
  final buffer = StringBuffer()
    ..writeln('书名：《$bookTitle》')
    ..writeln('章节：${segment.chapterTitle}（第 ${segment.chapterIndex + 1} 章，片段 ${segment.key}）');
  if (previousGist != null && previousGist.isNotEmpty) {
    buffer.writeln('上一片段梗概：$previousGist');
  }
  buffer
    ..writeln('原文：')
    ..writeln(segment.text)
    ..writeln()
    ..writeln('请提炼这一片段，输出 JSON：')
    ..writeln('{"points": ["3-6 条情节或论述要点"], '
        '"entities": ["出现的人物、地点、概念"], '
        '"toneCues": ["情感色彩线索，如叙述者态度、情绪转折"], '
        '"quotes": ["1-3 句逐字原句，每句不超过 150 字"]}');
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(LlmRole.user, buffer.toString()),
  ];
}

List<LlmMessage> reducePartPrompt(
  DistillPart part, {
  required String bookTitle,
}) {
  final buffer = StringBuffer()
    ..writeln('书名：《$bookTitle》')
    ..writeln('下面是一组相邻章节的原文片段，按章节顺序排列，片段之间用 === 分隔。')
    ..writeln();
  for (final segment in part.segments) {
    buffer
      ..writeln('=== 第 ${segment.chapterIndex + 1} 章 ${segment.chapterTitle}（${segment.key}）')
      ..writeln(segment.text);
  }
  buffer
    ..writeln()
    ..writeln('请为这一组章节写压缩梗概，输出 JSON：')
    ..writeln('{"summary": "整组章节的连贯梗概，200-400 字", '
        '"chapters": [{"chapterIndex": 0, "title": "章节标题", "gist": "该章 60-120 字梗概"}]}');
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(LlmRole.user, buffer.toString()),
  ];
}

List<LlmMessage> overviewPrompt(
  List<String> partSummaries, {
  required String bookTitle,
  required String author,
}) {
  final buffer = StringBuffer()
    ..writeln('书名：《$bookTitle》')
    ..writeln('作者：${author.isEmpty ? '未知' : author}')
    ..writeln('全书按顺序分成若干组，下面是每组的梗概：')
    ..writeln();
  for (var i = 0; i < partSummaries.length; i++) {
    buffer
      ..writeln('【第 ${i + 1} 组】')
      ..writeln(partSummaries[i]);
  }
  buffer
    ..writeln()
    ..writeln('请把这些梗概综合成全书总览，输出 JSON：')
    ..writeln('{"oneLiner": "一句话说明这本书讲什么", '
        '"synopsis": "600-900 字全书梗概，按时间或论述顺序讲清主要人物、核心事件与结局走向", '
        '"themes": ["3-6 个主题"], '
        '"structure": [{"title": "部分名称", "chapters": [0, 1], "note": "这一部分的作用"}], '
        '"argument": "作者想表达的核心观点或情感态度"}');
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(LlmRole.user, buffer.toString()),
  ];
}

List<LlmMessage> tonePrompt(
  List<String> partSummaries, {
  required String bookTitle,
}) {
  final buffer = StringBuffer()
    ..writeln('书名：《$bookTitle》')
    ..writeln('下面是全书分组的梗概：')
    ..writeln();
  for (var i = 0; i < partSummaries.length; i++) {
    buffer
      ..writeln('【第 ${i + 1} 组】')
      ..writeln(partSummaries[i]);
  }
  buffer
    ..writeln()
    ..writeln('请判断全书的语气与情感走向，输出 JSON：')
    ..writeln('{"overall": "整体情感基调，如克制、悲悯、讽刺", '
        '"narrator": "叙述者是谁、与故事的距离、可信度", '
        '"arc": [{"chapterIndex": 0, "tone": "这一阶段的情绪与氛围"}], '
        '"style": ["语言风格特征，如短句、白描、方言"], '
        '"sampleQuotes": ["1-3 句体现语气特征的原句，每句不超过 150 字"]}');
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(LlmRole.user, buffer.toString()),
  ];
}

List<LlmMessage> cardsPrompt(
  List<String> candidates, {
  required String bookTitle,
}) {
  final buffer = StringBuffer()
    ..writeln('书名：《$bookTitle》')
    ..writeln('下面是候选素材，每条是一个章节组的要点与原句：')
    ..writeln();
  for (final candidate in candidates) {
    buffer
      ..writeln('---')
      ..writeln(candidate);
  }
  buffer
    ..writeln()
    ..writeln('请提炼 3-8 张「陪读卡片」，覆盖框架、原理、案例、反例、术语五类，输出 JSON 数组：')
    ..writeln('[{"slug": "英文小写连字符", "title": "卡片标题", '
        '"type": "framework|principle|case|counter-example|glossary", '
        '"definition": "80-150 字说明，可迁移到陪读对话中使用", '
        '"sourceChapters": [0, 2], "quote": "支撑这张卡片的逐字原句，不超过 150 字"}]');
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(LlmRole.user, buffer.toString()),
  ];
}

List<LlmMessage> verifyPrompt(String cardJson, String sourceText) {
  return [
    const LlmMessage(LlmRole.system, distillSystemPrompt),
    LlmMessage(
      LlmRole.user,
      '请核对下面这张卡片是否被原文支持。\n\n卡片：\n$cardJson\n\n原文：\n$sourceText\n\n'
      '输出 JSON：{"supported": true, "reason": "一句话说明依据", "quoteFound": true}',
    ),
  ];
}

// ---------------------------------------------------------------- parsing

MapResult parseMapResult(String raw) {
  final json = _decodeObject(raw, '片段提炼');
  return MapResult(
    points: _strings(json['points']),
    entities: _strings(json['entities']),
    toneCues: _strings(json['toneCues']),
    quotes: _strings(json['quotes']),
  );
}

PartResult parsePartResult(String raw) {
  final json = _decodeObject(raw, '章节梗概');
  final chapters = <ChapterGist>[];
  final list = json['chapters'];
  if (list is List) {
    for (final item in list) {
      if (item is! Map) continue;
      final index = _int(item['chapterIndex']);
      if (index == null) continue;
      chapters.add(
        ChapterGist(
          chapterIndex: index,
          title: _string(item['title']) ?? '',
          gist: _string(item['gist']) ?? '',
        ),
      );
    }
  }
  return PartResult(
    summary: _string(json['summary']) ?? '',
    chapters: chapters,
  );
}

BookOverview parseOverview(String raw) {
  final json = _decodeObject(raw, '全书总览');
  final structure = <ThemeArc>[];
  final arcs = json['structure'];
  if (arcs is List) {
    for (final item in arcs) {
      if (item is! Map) continue;
      structure.add(
        ThemeArc(
          title: _string(item['title']) ?? '',
          chapters: _ints(item['chapters']),
          note: _string(item['note']) ?? '',
        ),
      );
    }
  }
  return BookOverview(
    oneLiner: _string(json['oneLiner']) ?? '',
    synopsis: _string(json['synopsis']) ?? '',
    themes: _strings(json['themes']),
    structure: structure,
    argument: _string(json['argument']) ?? '',
  );
}

ToneProfile parseTone(String raw) {
  final json = _decodeObject(raw, '语气画像');
  final arc = <ToneArc>[];
  final items = json['arc'];
  if (items is List) {
    for (final item in items) {
      if (item is! Map) continue;
      final index = _int(item['chapterIndex']);
      if (index == null) continue;
      arc.add(ToneArc(chapterIndex: index, tone: _string(item['tone']) ?? ''));
    }
  }
  return ToneProfile(
    overall: _string(json['overall']) ?? '',
    narrator: _string(json['narrator']) ?? '',
    arc: arc,
    style: _strings(json['style']),
    sampleQuotes: _strings(json['sampleQuotes']),
  );
}

List<DistillCard> parseCards(String raw) {
  final decoded = _decodeAny(raw, '陪读卡片');
  final list = decoded is List ? decoded : (decoded is Map ? decoded['cards'] : null);
  if (list is! List) {
    throw DistillParseException('陪读卡片应为 JSON 数组', raw: raw);
  }
  final cards = <DistillCard>[];
  for (final item in list) {
    if (item is! Map) continue;
    final slug = _string(item['slug']);
    final title = _string(item['title']);
    if (slug == null || title == null) continue;
    cards.add(
      DistillCard(
        slug: slug,
        title: title,
        type: _string(item['type']) ?? 'case',
        definition: _string(item['definition']) ?? '',
        sourceChapters: _ints(item['sourceChapters']),
        quote: _string(item['quote']),
      ),
    );
  }
  return cards;
}

Map<String, Object?> _decodeObject(String raw, String what) {
  final decoded = _decodeAny(raw, what);
  if (decoded is Map<String, Object?>) return decoded;
  throw DistillParseException('$what 应为 JSON 对象', raw: raw);
}

Object? _decodeAny(String raw, String what) {
  final text = _jsonSlice(raw);
  try {
    return jsonDecode(text);
  } on FormatException catch (error) {
    throw DistillParseException('$what 不是合法 JSON：${error.message}', raw: raw);
  }
}

/// Strips code fences and any chatter around the JSON payload.
String _jsonSlice(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) {
    text = fence.group(1)!.trim();
  }
  final firstBrace = text.indexOf('{');
  final firstBracket = text.indexOf('[');
  var start = -1;
  if (firstBrace >= 0 && (firstBracket < 0 || firstBrace < firstBracket)) {
    start = firstBrace;
  } else if (firstBracket >= 0) {
    start = firstBracket;
  }
  if (start < 0) return text;

  final endBrace = text.lastIndexOf('}');
  final endBracket = text.lastIndexOf(']');
  final end = endBrace > endBracket ? endBrace : endBracket;
  if (end <= start) return text.substring(start);
  return text.substring(start, end + 1);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

List<int> _ints(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (_int(item) != null) _int(item)!,
  ];
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _string(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}
