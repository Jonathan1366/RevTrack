import 'package:flutter/services.dart';

const downloadsFile = false;
Future<void> exportCsv(String csv) =>
    Clipboard.setData(ClipboardData(text: csv));
