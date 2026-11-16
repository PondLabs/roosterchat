import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// `dart:io`'s client, keeping an idle connection for [idle].
HttpClient keepAliveIoClient(Duration idle) => HttpClient()..idleTimeout = idle;

http.Client keepAliveHttpClient(Duration idle) =>
    IOClient(keepAliveIoClient(idle));
