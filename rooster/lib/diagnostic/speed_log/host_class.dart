/// Which kind of server a request went to. The speed log keeps this instead
/// of the host name.
enum HostClass {
  homeserver('homeserver'),
  tokenService('token_service'),
  sfu('sfu'),
  other('other');

  const HostClass(this.label);

  /// How the report writes it.
  final String label;
}

/// Tells which [HostClass] a URL belongs to.
///
/// The homeserver is looked up when a request is made, because a client
/// learns it during login. The call services are registered by the call code
/// once it knows them (`HostClassifier.register(focusUrl, HostClass.tokenService)`);
/// the registry is shared by every account and holds at most
/// [_maxRegistered] hosts, in memory only.
class HostClassifier {
  HostClassifier({Uri? Function()? homeserver}) : _homeserver = homeserver;

  final Uri? Function()? _homeserver;

  static const _maxRegistered = 32;
  static final Map<String, HostClass> _registered = {};

  static String _key(Uri url) => '${url.host}:${url.port}';

  static void register(Uri url, HostClass hostClass) {
    if (_registered.length >= _maxRegistered) _registered.clear();
    _registered[_key(url)] = hostClass;
  }

  HostClass classify(Uri url) {
    final homeserver = _homeserver?.call();
    if (homeserver != null && _key(homeserver) == _key(url)) {
      return HostClass.homeserver;
    }
    return _registered[_key(url)] ?? HostClass.other;
  }
}
