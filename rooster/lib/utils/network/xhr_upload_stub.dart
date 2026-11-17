import 'package:http/http.dart' as http;

/// Whether uploads can go through `XMLHttpRequest` here: only on the web.
const bool xhrUploadAvailable = false;

/// A body made ready for `XMLHttpRequest`: none here.
class XhrBody {}

Future<XhrBody?> prepareXhrBody(http.BaseRequest request) async => null;

Future<http.StreamedResponse> sendByXhr(
  http.BaseRequest request, {
  required void Function() onHeaders,
  required void Function(int sentBytes) onUploadProgress,
  required void Function() onUploadLoad,
  Future<void>? abort,
  XhrBody? prepared,
}) =>
    throw UnsupportedError('XMLHttpRequest exists only on the web');
