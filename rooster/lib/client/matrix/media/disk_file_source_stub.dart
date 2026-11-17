import 'package:matrix/matrix.dart' as matrix;

/// No file is read from disk here (the web has no paths): a file is sent
/// from the bytes it was read into.
Future<matrix.FileSendSource?> diskFileSource(String path) async => null;
