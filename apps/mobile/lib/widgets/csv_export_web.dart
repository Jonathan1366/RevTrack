import 'dart:js_interop';
import 'package:web/web.dart' as web;

const downloadsFile = true;
Future<void> exportCsv(String csv) async {
  final blob = web.Blob(
    [('\uFEFF$csv').toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'revtrack-telemetry.csv';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
