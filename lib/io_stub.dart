class File {
  final String path;

  const File(this.path);

  Future<List<int>> readAsBytes() async {
    throw UnsupportedError('Native file access is not available on this platform.');
  }
}
