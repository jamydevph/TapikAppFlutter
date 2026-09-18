import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:tapikappflutter/core/error/failure.dart';
import 'package:tapikappflutter/core/theme/app_theme_mode.dart';
import 'package:tapikappflutter/data/models/device_model.dart';
import 'package:tapikappflutter/data/models/settings_model.dart';
import 'package:tapikappflutter/data/repositories/auth_repository.dart';
import 'package:tapikappflutter/data/repositories/device_repository.dart';
import 'package:tapikappflutter/data/repositories/settings_repository.dart';
import 'package:tapikappflutter/data/sources/firebase_auth_source.dart';
import 'package:tapikappflutter/data/sources/firestore_source.dart';
import 'package:tapikappflutter/data/sources/local_prefs_source.dart';
import 'package:tapikappflutter/features/auth/view_model/auth_cubit.dart';
import 'package:tapikappflutter/features/auth/view_model/auth_state.dart';
import 'package:tapikappflutter/features/auth/view_model/password_reset_cubit.dart';
import 'package:tapikappflutter/features/auth/view_model/password_reset_state.dart';
import 'package:tapikappflutter/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(HarnessApp(supported: isMobile));
}

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key, required this.supported});

  final bool supported;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tapikapp Firebase Harness',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: supported
          ? const HarnessPage()
          : const Scaffold(
              body: Center(
                child: Text('Run this harness on Android or iOS.'),
              ),
            ),
    );
  }
}

enum StepStatus { pending, running, passed, failed, skipped }

class HarnessStep {
  HarnessStep(this.name, this.run, {this.alwaysRun = false});

  final String name;
  final Future<String> Function() run;
  final bool alwaysRun;
  StepStatus status = StepStatus.pending;
  String detail = '';
}

class HarnessFailure implements Exception {
  HarnessFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class CountingFirestoreSource extends FirestoreSource {
  int settingsWrites = 0;

  @override
  Future<void> setSettings(String uid, Map<String, dynamic> data) {
    settingsWrites++;
    return super.setSettings(uid, data);
  }
}

class FirebaseHarness {
  FirebaseHarness()
      : email =
            'harness.${DateTime.now().millisecondsSinceEpoch}@example.com';

  static const String password = 'Harness#12345';
  static const String deviceId = 'harness-laptop';
  static const String fingerprint = 'sha256:harness-fingerprint';
  static const String foreignUid = 'not-my-uid-harness';

  final String email;
  final FirebaseAuthSource auth = FirebaseAuthSource();
  final CountingFirestoreSource firestore = CountingFirestoreSource();
  final LocalPrefsSource prefs = LocalPrefsSource();
  late final AuthRepository authRepository =
      AuthRepository(source: auth, firestore: firestore);
  late final AuthCubit cubit = AuthCubit(
    repository: authRepository,
    prefs: prefs,
  );
  late final PasswordResetCubit passwordResetCubit =
      PasswordResetCubit(authRepository);
  late final DeviceRepository devices =
      DeviceRepository(auth: auth, firestore: firestore);
  late final SettingsRepository settings = SettingsRepository(
    auth: auth,
    firestore: firestore,
    debounce: const Duration(milliseconds: 300),
  );

  String? uid;

  List<HarnessStep> buildSteps() {
    return [
      HarnessStep('Sign up creates the auth user + profile doc', signUp),
      HarnessStep('Sign out clears the login-once flag', signOut),
      HarnessStep('Signed-out repository access is an AuthFailure',
          signedOutGuard),
      HarnessStep('Password reset request is accepted', passwordReset),
      HarnessStep('Sign in restores the session + flag', signIn),
      HarnessStep('Device registry: register, trust, touch, revoke',
          deviceRegistry),
      HarnessStep('Settings: 20 rapid updates become 1 debounced write',
          settingsDebounce),
      HarnessStep('Settings: a second device reads only the changed fields',
          settingsReadBack),
      HarnessStep('Rules reject a foreign uid (read + write)', rulesRejectForeignUid),
      HarnessStep('Cleanup: delete harness data + user', cleanup,
          alwaysRun: true),
    ];
  }

  void check(bool condition, String message) {
    if (!condition) {
      throw HarnessFailure(message);
    }
  }

  static bool _isHarnessEmail(String? value) {
    return value != null &&
        value.startsWith('harness.') &&
        value.endsWith('@example.com');
  }

  Future<String> signUp() async {
    final existing = FirebaseAuth.instance.currentUser;
    check(
      existing == null || _isHarnessEmail(existing.email),
      'Device is signed in as ${existing?.email}; sign out of the app before running the harness',
    );
    await cubit.signUp(email: email, password: password);
    final state = cubit.state;
    check(state is Authenticated, 'Expected Authenticated, got $state');
    uid = (state as Authenticated).user.uid;
    final profile =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    check(profile.exists, 'Profile doc users/$uid was not written');
    check(profile.data()?['email'] == email, 'Profile email mismatch');
    check(await prefs.isLoggedIn(), 'login-once flag should be true');
    return 'uid=$uid · profile doc exists · loggedIn=true';
  }

  Future<String> signOut() async {
    await cubit.signOut();
    check(cubit.state is Unauthenticated, 'Expected Unauthenticated');
    check(auth.currentUser == null, 'FirebaseAuth still has a user');
    check(!await prefs.isLoggedIn(), 'login-once flag should be false');
    return 'currentUser=null · loggedIn=false';
  }

  Future<String> signedOutGuard() async {
    try {
      await devices.loadTrusted();
    } on AuthFailure catch (failure) {
      return 'AuthFailure: "${failure.message}"';
    }
    throw HarnessFailure('loadTrusted() succeeded while signed out');
  }

  Future<String> passwordReset() async {
    await passwordResetCubit.send(email);
    final state = passwordResetCubit.state;
    check(state is PasswordResetSent, 'Expected PasswordResetSent, got $state');
    return 'request accepted for $email (delivery not verifiable here)';
  }

  Future<String> signIn() async {
    await cubit.signIn(email: email, password: password);
    final state = cubit.state;
    check(state is Authenticated, 'Expected Authenticated, got $state');
    check((state as Authenticated).user.uid == uid, 'uid changed on sign-in');
    check(await prefs.isLoggedIn(), 'login-once flag should be true');
    return 'same uid · loggedIn=true';
  }

  Future<String> deviceRegistry() async {
    await devices.registerDevice(const DeviceModel(
      id: deviceId,
      name: 'Harness MacBook',
      platform: 'macos',
      certFingerprint: fingerprint,
    ));
    var trusted = await devices.loadTrusted();
    final match = trusted.where((d) => d.id == deviceId).toList();
    check(match.length == 1, 'Registered device not found in loadTrusted()');
    check(match.first.certFingerprint == fingerprint, 'Fingerprint mismatch');
    final fingerprints = await devices.trustedFingerprints();
    check(fingerprints.contains(fingerprint),
        'trustedFingerprints() missing the fingerprint');
    await devices.touchLastSeen(deviceId);
    await devices.revokeDevice(deviceId);
    trusted = await devices.loadTrusted();
    check(trusted.every((d) => d.id != deviceId), 'Revoked device still listed');
    final stamps = match.first.trustedAt == null
        ? 'timestamps pending'
        : 'trustedAt=${match.first.trustedAt!.toIso8601String()}';
    return 'registered → trusted (1) → fingerprint pinned → touched → revoked (0) · $stamps';
  }

  Future<String> settingsDebounce() async {
    final initial = await settings.load();
    check(initial == SettingsModel.defaults, 'Fresh account should read defaults');
    firestore.settingsWrites = 0;
    for (var i = 0; i < 20; i++) {
      settings.update(settings.current.copyWith(
        sensitivity: 0.5 + i * 0.1,
        themeMode: i == 19 ? AppThemeMode.dark : null,
      ));
    }
    check(settings.hasPendingWrite, 'Updates should be pending, not written');
    check(firestore.settingsWrites == 0, 'A write happened before the debounce');
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (settings.hasPendingWrite && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(!settings.hasPendingWrite, 'Debounced write never completed');
    check(firestore.settingsWrites == 1,
        'Expected exactly 1 write, got ${firestore.settingsWrites}');
    return '20 update() calls → ${firestore.settingsWrites} setSettings() · sensitivity=${settings.current.sensitivity.toStringAsFixed(1)} · theme=${settings.current.themeMode.name}';
  }

  Future<String> settingsReadBack() async {
    final other = SettingsRepository(auth: auth, firestore: firestore);
    final loaded = await other.load();
    await other.dispose();
    check((loaded.sensitivity - 2.4).abs() < 0.001,
        'Expected sensitivity 2.4, got ${loaded.sensitivity}');
    check(loaded.themeMode == AppThemeMode.dark, 'Expected themeMode dark');
    check(loaded.naturalScrolling && loaded.hapticFeedback,
        'Untouched fields should keep their defaults');
    final raw = await FirebaseFirestore.instance
        .doc('users/$uid/settings/preferences')
        .get();
    final keys = (raw.data() ?? {}).keys.toList()..sort();
    check(!keys.contains('naturalScrolling') && !keys.contains('hapticFeedback'),
        'Untouched fields were written: $keys');
    return 'second instance reads sensitivity=2.4, theme=dark · doc fields=$keys';
  }

  Future<String> rulesRejectForeignUid() async {
    final foreign = FirebaseFirestore.instance
        .doc('users/$foreignUid/settings/preferences');
    final readCode = await _deniedCode(() => foreign.get());
    final writeCode = await _deniedCode(() => foreign.set({'sensitivity': 3.0}));
    var junk = '';
    if (writeCode != 'permission-denied') {
      final deleteCode = await _deniedCode(() => foreign.delete());
      junk = deleteCode == 'allowed'
          ? ' · junk doc deleted'
          : ' · junk doc left behind: $deleteCode';
    }
    check(readCode == 'permission-denied' && writeCode == 'permission-denied',
        'Foreign read → $readCode · write → $writeCode$junk');
    return 'read=permission-denied · write=permission-denied';
  }

  Future<String> _deniedCode(Future<Object?> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 15));
    } on FirebaseException catch (error) {
      return error.code;
    } on TimeoutException {
      return 'timeout';
    }
    return 'allowed';
  }

  Future<String> cleanup() async {
    final notes = <String>[];
    final errors = <String>[];
    var ownedSession = false;
    try {
      if (FirebaseAuth.instance.currentUser == null && uid != null) {
        await cubit.signIn(email: email, password: password);
      }
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && !_isHarnessEmail(current.email)) {
        notes.add('signed-in user ${current.email} is not a harness user; left untouched');
      } else if (current != null) {
        ownedSession = true;
        final root = FirebaseFirestore.instance.collection('users').doc(current.uid);
        try {
          final devicesSnapshot = await root.collection('devices').get();
          for (final doc in devicesSnapshot.docs) {
            await doc.reference.delete();
          }
          await root.collection('settings').doc('preferences').delete();
          await root.delete();
          notes.add('Firestore subtree deleted');
        } catch (error) {
          errors.add('users/${current.uid} NOT deleted: $error');
        }
        try {
          await current.delete();
          notes.add('auth user deleted');
        } catch (error) {
          errors.add('auth user ${current.email} NOT deleted: $error');
          await FirebaseAuth.instance.signOut();
          notes.add('signed out');
        }
      } else if (uid != null) {
        ownedSession = true;
        final state = cubit.state;
        final reason = state is AuthError ? state.message : '$state';
        errors.add(
          're-sign-in failed ($reason); $email (uid=$uid) and users/$uid were NOT deleted',
        );
      } else {
        ownedSession = true;
        notes.add('nothing was created');
      }
    } finally {
      if (ownedSession) {
        await prefs.setLoggedIn(false);
      }
      await settings.dispose();
      await cubit.close();
      await passwordResetCubit.close();
    }
    if (errors.isNotEmpty) {
      throw HarnessFailure([...notes, ...errors].join(' · '));
    }
    return notes.join(' · ');
  }
}

class HarnessPage extends StatefulWidget {
  const HarnessPage({super.key});

  @override
  State<HarnessPage> createState() => _HarnessPageState();
}

class _HarnessPageState extends State<HarnessPage> {
  List<HarnessStep> _steps = const [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    final harness = FirebaseHarness();
    setState(() {
      _steps = harness.buildSteps();
      _running = true;
    });
    var failed = false;
    for (final step in _steps) {
      if (failed && !step.alwaysRun) {
        setState(() => step.status = StepStatus.skipped);
        continue;
      }
      setState(() => step.status = StepStatus.running);
      try {
        final detail = await step.run();
        setState(() {
          step.status = StepStatus.passed;
          step.detail = detail;
        });
      } catch (error) {
        failed = true;
        setState(() {
          step.status = StepStatus.failed;
          step.detail = error is Failure
              ? '${error.runtimeType}: ${error.message}'
              : error.toString();
        });
      }
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final passed = _steps.where((s) => s.status == StepStatus.passed).length;
    final failedCount = _steps.where((s) => s.status == StepStatus.failed).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase layer harness')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _running
                  ? 'Running… $passed/${_steps.length} passed'
                  : '$passed/${_steps.length} passed · $failedCount failed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _steps.length,
              itemBuilder: (context, index) {
                final step = _steps[index];
                return ListTile(
                  leading: _icon(step.status),
                  title: Text(step.name),
                  subtitle: step.detail.isEmpty ? null : Text(step.detail),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _running ? null : _runAll,
        child: const Icon(Icons.replay),
      ),
    );
  }

  Widget _icon(StepStatus status) {
    switch (status) {
      case StepStatus.pending:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
      case StepStatus.running:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StepStatus.passed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case StepStatus.failed:
        return const Icon(Icons.cancel, color: Colors.red);
      case StepStatus.skipped:
        return const Icon(Icons.remove_circle_outline, color: Colors.orange);
    }
  }
}
