import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google identity is separate from fleet access. Never substitute an ID token
/// for the demo API credential or grant a workspace based on client-side claims.
class GoogleAuthController extends ChangeNotifier {
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  final GoogleSignIn _google = GoogleSignIn.instance;
  Future<void>? _initialization;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool busy = false, ready = false, _disposed = false;
  String? message;
  GoogleSignInAccount? account;

  bool get configured {
    if (kIsWeb) return webClientId.isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => serverClientId.isNotEmpty,
      TargetPlatform.iOS || TargetPlatform.macOS => iosClientId.isNotEmpty,
      _ => false,
    };
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> prepare() async {
    if (!configured) {
      message =
          'Login Google belum diaktifkan untuk RevTrack. '
          'Kamu tetap bisa mencoba tampilan aplikasi lewat demo.';
      _emit();
      return;
    }
    try {
      await (_initialization ??= _google.initialize(
        clientId: kIsWeb
            ? webClientId
            : defaultTargetPlatform == TargetPlatform.android ||
                  iosClientId.isEmpty
            ? null
            : iosClientId,
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      ));
      if (_disposed || ready) return;
      _events = _google.authenticationEvents.listen((event) {
        if (_disposed) return;
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            account = event.user;
            message = null;
          case GoogleSignInAuthenticationEventSignOut():
            account = null;
        }
        busy = false;
        _emit();
      }, onError: (Object error) => _failure(error));
      ready = true;
      message = null;
      _emit();
    } catch (error) {
      _initialization = null;
      _failure(error);
    }
  }

  Future<void> signIn() async {
    if (busy) return;
    busy = true;
    message = null;
    _emit();
    try {
      await prepare();
      if (!ready || _disposed) return;
      if (!_google.supportsAuthenticate()) return; // GIS button owns web flow.
      account = await _google.authenticate();
      message = null;
    } catch (error) {
      _failure(error);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> signOut() async {
    if (busy) return;
    busy = true;
    _emit();
    try {
      await _google.signOut();
      account = null;
      message = null;
    } catch (error) {
      _failure(error);
    } finally {
      busy = false;
      _emit();
    }
  }

  void _failure(Object error) {
    message = switch (error) {
      GoogleSignInException(code: GoogleSignInExceptionCode.canceled) =>
        'Masuk dibatalkan. Kamu bisa mencoba lagi kapan saja.',
      GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      ) ||
      GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
      ) => 'Login Google belum siap di perangkat ini. Silakan coba demo dulu.',
      _ => 'Belum bisa terhubung ke Google. Periksa koneksi, lalu coba lagi.',
    };
    busy = false;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    super.dispose();
  }
}
