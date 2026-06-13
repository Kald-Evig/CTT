// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$firebaseAuthStreamHash() =>
    r'3f6ad80a49c0a20aecc3fd383b3dac63b5176b3e';

/// Emite el usuario Firebase actual (null = sin sesión activa).
/// Usado por [estadoAuth] en app.dart para derivar el estado de navegación.
///
/// Copied from [firebaseAuthStream].
@ProviderFor(firebaseAuthStream)
final firebaseAuthStreamProvider = AutoDisposeStreamProvider<fb.User?>.internal(
  firebaseAuthStream,
  name: r'firebaseAuthStreamProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$firebaseAuthStreamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FirebaseAuthStreamRef = AutoDisposeStreamProviderRef<fb.User?>;
String _$authNotifierHash() => r'df8358ae84f6f312dad820484b600da1a5a53041';

/// See also [AuthNotifier].
@ProviderFor(AuthNotifier)
final authNotifierProvider =
    AutoDisposeAsyncNotifierProvider<AuthNotifier, void>.internal(
  AuthNotifier.new,
  name: r'authNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AuthNotifier = AutoDisposeAsyncNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
