enum DownloadStatus { pending, downloading, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final String name;
  final String url;
  final List<String> fallbackUrls;
  final String destinationPath;
  final String? sha1;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;
  int retryCount;
  final DateTime startTime;
  DateTime? endTime;

  DownloadTask({
    String? id,
    required this.name,
    required this.url,
    this.fallbackUrls = const [],
    required this.destinationPath,
    this.sha1,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
    DateTime? startTime,
    this.endTime,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        startTime = startTime ?? DateTime.now();

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes * 100 : 0;
  
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
  
  double get speed => duration.inSeconds > 0 ? downloadedBytes / duration.inSeconds : 0;
}

class DownloadGroup {
  final String id;
  final String name;
  final List<DownloadTask> tasks;
  DownloadStatus status;

  DownloadGroup({
    String? id,
    required this.name,
    List<DownloadTask>? tasks,
    this.status = DownloadStatus.pending,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        tasks = tasks ?? [];

  int get totalTasks => tasks.length;
  int get completedTasks => tasks.where((t) => t.status == DownloadStatus.completed).length;
  int get failedTasks => tasks.where((t) => t.status == DownloadStatus.failed).length;
  int get totalBytes => tasks.fold(0, (sum, t) => sum + t.totalBytes);
  int get downloadedBytes => tasks.fold(0, (sum, t) => sum + t.downloadedBytes);
  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes * 100 : 0;
}
