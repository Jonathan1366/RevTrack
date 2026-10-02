import 'dart:convert';
import 'dart:io';

Never _fail(String message) {
  stderr.writeln('RevTrack config error: $message');
  exit(2);
}

void main(List<String> args) {
  if (args.length != 1) {
    _fail('usage: dart run tool/validate_mobile_config.dart <config.json>');
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    _fail('config file not found: ${file.path}');
  }

  Object decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    _fail('invalid JSON in ${file.path}: ${error.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    _fail('config root must be a JSON object');
  }

  final map = decoded;
  final token = (map['MAPBOX_ACCESS_TOKEN'] ?? '').toString().trim();
  final style = (map['MAPBOX_STYLE_URI'] ?? '').toString().trim();
  final apiUrl = (map['API_URL'] ?? '').toString().trim();

  if (!token.startsWith('pk.') || token.contains('replace-with')) {
    _fail('MAPBOX_ACCESS_TOKEN must be a real public Mapbox token beginning with pk.');
  }
  if (!style.startsWith('mapbox://styles/')) {
    _fail('MAPBOX_STYLE_URI must begin with mapbox://styles/.');
  }

  if (apiUrl.isNotEmpty) {
    final uri = Uri.tryParse(apiUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _fail('API_URL must be empty or a valid absolute URL.');
    }
    final loopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (!loopback && uri.scheme != 'https') {
      _fail('non-loopback API_URL must use HTTPS for an Android release build.');
    }
    if (loopback) {
      stdout.writeln(
        'Warning: API_URL uses loopback. Fleet API will require adb reverse and a running local backend; Mapbox remains online.',
      );
    }
  } else {
    stdout.writeln(
      'Info: API_URL is empty. The Android build will use local demo fleet data while Mapbox runs online.',
    );
  }

  stdout.writeln('RevTrack mobile config OK: Mapbox enabled for release build.');
}
