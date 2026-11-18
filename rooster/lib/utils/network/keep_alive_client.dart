import 'package:http/http.dart' as http;
import 'package:rooster/utils/network/keep_alive_client_web.dart'
    if (dart.library.io) 'package:rooster/utils/network/keep_alive_client_io.dart'
    as platform;

/// An HTTP client that keeps an idle connection open for [idle] instead of
/// `dart:io`'s 15 s, so a request made within it skips the TCP and TLS
/// handshakes. In a browser the browser keeps its connections, and this is
/// a plain [http.Client].
http.Client keepAliveHttpClient(Duration idle) =>
    platform.keepAliveHttpClient(idle);
