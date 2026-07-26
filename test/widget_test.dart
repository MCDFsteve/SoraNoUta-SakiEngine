import 'package:flutter_test/flutter_test.dart';
import 'package:soranouta_project/soranouta/soranouta_module.dart';

void main() {
  test('project module factory exposes the SoraNoUta entry metadata', () async {
    final module = createProjectModule();

    expect(module, isA<SoranoutaModule>());
    expect(await module.getAppTitle(), 'SoraNoUta');
    expect(module.initialScript, isNotEmpty);
    expect(module.enableDebugFeatures, isTrue);
  });
}
