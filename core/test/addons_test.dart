import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cml_core/cml_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('manifest with BOM parses', () {
    final m = AddonManager.parseManifest('\uFEFF{"version":"1","addons":[{"id":"pulse-ai-models","version":"1","asset":"a.zip"}]}');
    expect((m['addons'] as List).single['id'], 'pulse-ai-models');
  });

  test('installZip keeps sub-folders and records the version', () async {
    final tmp = await Directory.systemTemp.createTemp('cml_addon');
    try {
      final root = p.join(tmp.path, 'addons');
      final zip = File(p.join(tmp.path, 'a.zip'));
      final enc = ZipFileEncoder()..create(zip.path);
      enc.addArchiveFile(ArchiveFile('models/rvc.onnx', 3, [1, 2, 3]));
      enc.closeSync();
      AddonManager.rootOverride = root;
      await AddonManager.installZip('pulse-ai-models', '0.2.0', zip);
      expect(AddonManager.isInstalled('pulse-ai-models'), isTrue);
      expect(await AddonManager.installedVersion('pulse-ai-models'), '0.2.0');
      expect(File(p.join(root, 'pulse-ai-models', 'models', 'rvc.onnx')).existsSync(), isTrue);
      expect(File(p.join(root, 'pulse-ai-models', 'cml-addon.json')).existsSync(), isTrue);
    } finally {
      AddonManager.rootOverride = null;
      await tmp.delete(recursive: true);
    }
  });
}
