import 'package:http/http.dart' as http;

/// Whether uploads can go through `XMLHttpRequest` here: only on the web.
const bool xhrUploadAvailable = false;

Future<http.StreamedResponse> sendByXhr(
  http.BaseRequest request, {
  required void Function() onHeaders,
  required void Function() onUploadLoad,
}) =>
    throw UnsupportedError('XMLHttpRequest exists only on the web');
