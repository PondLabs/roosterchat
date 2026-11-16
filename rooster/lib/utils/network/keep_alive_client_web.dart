import 'package:http/http.dart' as http;

/// The browser keeps its own connections: nothing to set.
http.Client keepAliveHttpClient(Duration idle) => http.Client();
