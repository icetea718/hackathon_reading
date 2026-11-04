import 'dart:io';

class IllustrationPlan {
  const IllustrationPlan({
    required this.medium,
    required this.sketchPrompt,
    required this.colorPrompt,
  });

  final String medium;
  final String sketchPrompt;
  final String colorPrompt;
}

class IllustrationResult {
  const IllustrationResult({
    required this.plan,
    required this.sketchFile,
    required this.finalFile,
  });

  final IllustrationPlan plan;
  final File sketchFile;
  final File finalFile;
}

enum IllustrationStage { planning, sketching, coloring }

extension IllustrationStageLabel on IllustrationStage {
  String get label => switch (this) {
        IllustrationStage.planning => '正在分析文段，规划画面…',
        IllustrationStage.sketching => '正在绘制草图线稿…',
        IllustrationStage.coloring => '正在上色，渲染手绘质感…',
      };
}

class IllustrationException implements Exception {
  IllustrationException(this.message);

  final String message;

  @override
  String toString() => message;
}
