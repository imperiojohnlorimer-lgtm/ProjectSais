import 'csv.dart';
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download.dart'
    as web_download;

/// Saves [rows] as [fileName] (a .csv) through the browser's download.
void saveCsv(String fileName, List<List<Object?>> rows) =>
    web_download.WebDownloadUtils.downloadBytes(fileName, csvBytes(rows));
