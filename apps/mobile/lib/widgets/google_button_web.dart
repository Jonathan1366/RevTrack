import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as google;

Widget googleWebButton() => google.renderButton(
  configuration: google.GSIButtonConfiguration(
    theme: google.GSIButtonTheme.outline,
    size: google.GSIButtonSize.large,
    text: google.GSIButtonText.continueWith,
    shape: google.GSIButtonShape.pill,
    minimumWidth: 280,
    locale: 'id',
  ),
);
