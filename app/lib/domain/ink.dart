/// Paper geometry and the records the rest of the app stores.
///
/// This library is pure Dart. Colors are ARGB ints so nothing here imports
/// Flutter.
library;

/// Active area of the donor tablet, in millimeters.
const double pageWidthMm = 170;
const double pageHeightMm = 107;
const double pageAspect = pageWidthMm / pageHeightMm;

/// Pen pressure on the wire and in stored points.
const int maxPressure = 16383;

/// Notebook names are a single line the user typed.
const int maxNotebookNameLength = 200;

/// Whether a saved record still needs to be uploaded.
///
/// The flag lives on the record itself so a later save cannot update the
/// ink and forget the upload, or the other way around.
enum SyncState { pending, synced }

class PaperRect {
  const PaperRect({
    this.leftMm = 0,
    this.topMm = 0,
    this.widthMm = pageWidthMm,
    this.heightMm = pageHeightMm,
  });

  final double leftMm;
  final double topMm;
  final double widthMm;
  final double heightMm;

  static const fullPage = PaperRect();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaperRect &&
        other.leftMm == leftMm &&
        other.topMm == topMm &&
        other.widthMm == widthMm &&
        other.heightMm == heightMm;
  }

  @override
  int get hashCode => Object.hash(leftMm, topMm, widthMm, heightMm);
}

class StrokePoint {
  StrokePoint({
    required double xMm,
    required double yMm,
    required int pressure,
    required this.touching,
    this.tMs = 0,
    this.approximateTime = false,
  }) : xMm = xMm.clamp(0, pageWidthMm).toDouble(),
       yMm = yMm.clamp(0, pageHeightMm).toDouble(),
       pressure = _checkedPressure(pressure);

  final double xMm;
  final double yMm;
  final int pressure;
  final bool touching;
  final int tMs;

  /// True when the timestamp is the phone's arrival time because this boot
  /// had no live sample to anchor the pen's clock.
  final bool approximateTime;

  StrokePoint shift(double dxMm, double dyMm) {
    return StrokePoint(
      xMm: xMm + dxMm,
      yMm: yMm + dyMm,
      pressure: pressure,
      touching: touching,
      tMs: tMs,
      approximateTime: approximateTime,
    );
  }

  StrokePoint copy() => StrokePoint(
    xMm: xMm,
    yMm: yMm,
    pressure: pressure,
    touching: touching,
    tMs: tMs,
    approximateTime: approximateTime,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokePoint &&
        other.xMm == xMm &&
        other.yMm == yMm &&
        other.pressure == pressure &&
        other.touching == touching &&
        other.tMs == tMs &&
        other.approximateTime == approximateTime;
  }

  @override
  int get hashCode =>
      Object.hash(xMm, yMm, pressure, touching, tMs, approximateTime);
}

class Stroke {
  Stroke({
    required this.id,
    required List<StrokePoint> points,
    required this.colorArgb,
    required this.createdAt,
    DateTime? updatedAt,
    this.width = 1,
    this.version = 1,
    this.deletedAt,
    this.syncState = SyncState.pending,
  }) : points = List<StrokePoint>.unmodifiable(points),
       updatedAt = updatedAt ?? createdAt {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be >= 1');
    }
  }

  final String id;
  final List<StrokePoint> points;
  final int colorArgb;
  final double width;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncState syncState;

  bool get isDeleted => deletedAt != null;

  Stroke copyWith({
    List<StrokePoint>? points,
    int? colorArgb,
    double? width,
    DateTime? updatedAt,
    int? version,
    DateTime? deletedAt,
    SyncState? syncState,
  }) {
    return Stroke(
      id: id,
      points: points ?? this.points,
      colorArgb: colorArgb ?? this.colorArgb,
      width: width ?? this.width,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      syncState: syncState ?? this.syncState,
    );
  }

  /// Immutable snapshot. The point list cannot be edited in place.
  Stroke copy() =>
      copyWith(points: points.map((point) => point.copy()).toList());

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Stroke &&
        other.id == id &&
        _listEquals(other.points, points) &&
        other.colorArgb == colorArgb &&
        other.width == width &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.version == version &&
        other.deletedAt == deletedAt &&
        other.syncState == syncState;
  }

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(points),
    colorArgb,
    width,
    createdAt,
    updatedAt,
    version,
    deletedAt,
    syncState,
  );
}

class NotebookPage {
  NotebookPage({
    required this.id,
    required this.notebookId,
    required this.pageIndex,
    required List<Stroke> strokes,
    required this.createdAt,
    DateTime? capturedAt,
    this.paperRect = PaperRect.fullPage,
    this.recognizedText = '',
    List<String> markers = const [],
    this.syncState = SyncState.pending,
    DateTime? updatedAt,
    this.version = 1,
    this.deletedAt,
  }) : strokes = List<Stroke>.unmodifiable(strokes),
       markers = List<String>.unmodifiable(markers),
       capturedAt = capturedAt ?? createdAt,
       updatedAt = updatedAt ?? createdAt {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be >= 1');
    }
  }

  final String id;
  final String notebookId;
  final int pageIndex;
  final List<Stroke> strokes;
  final DateTime createdAt;
  final DateTime capturedAt;
  final PaperRect paperRect;
  final String recognizedText;

  /// Short notes written onto the page, such as "3 samples lost".
  final List<String> markers;
  final SyncState syncState;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  List<Stroke> get visibleStrokes => List<Stroke>.unmodifiable(
    strokes.where((stroke) => stroke.deletedAt == null),
  );

  NotebookPage copyWith({
    List<Stroke>? strokes,
    String? recognizedText,
    List<String>? markers,
    PaperRect? paperRect,
    DateTime? capturedAt,
    DateTime? updatedAt,
    int? version,
    DateTime? deletedAt,
    SyncState? syncState,
  }) {
    return NotebookPage(
      id: id,
      notebookId: notebookId,
      pageIndex: pageIndex,
      strokes: strokes ?? this.strokes,
      createdAt: createdAt,
      capturedAt: capturedAt ?? this.capturedAt,
      paperRect: paperRect ?? this.paperRect,
      recognizedText: recognizedText ?? this.recognizedText,
      markers: markers ?? this.markers,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      syncState: syncState ?? this.syncState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotebookPage &&
        other.id == id &&
        other.notebookId == notebookId &&
        other.pageIndex == pageIndex &&
        _listEquals(other.strokes, strokes) &&
        other.createdAt == createdAt &&
        other.capturedAt == capturedAt &&
        other.paperRect == paperRect &&
        other.recognizedText == recognizedText &&
        _listEquals(other.markers, markers) &&
        other.updatedAt == updatedAt &&
        other.version == version &&
        other.deletedAt == deletedAt &&
        other.syncState == syncState;
  }

  @override
  int get hashCode => Object.hash(
    id,
    notebookId,
    pageIndex,
    Object.hashAll(strokes),
    createdAt,
    capturedAt,
    paperRect,
    recognizedText,
    Object.hashAll(markers),
    updatedAt,
    version,
    deletedAt,
    syncState,
  );
}

class Notebook {
  Notebook({
    required this.id,
    required String name,
    required List<NotebookPage> pages,
    required this.inkColorArgb,
    required this.createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.syncState = SyncState.pending,
    this.version = 1,
  }) : name = _checkedName(name),
       pages = List<NotebookPage>.unmodifiable(pages),
       updatedAt = updatedAt ?? _latestActivity(createdAt, pages) {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be >= 1');
    }
  }

  final String id;
  final String name;
  final List<NotebookPage> pages;
  final int inkColorArgb;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncState syncState;
  final int version;

  bool get isDeleted => deletedAt != null;

  DateTime get latestActivity => _latestActivity(createdAt, pages);

  Notebook copyWith({
    String? name,
    List<NotebookPage>? pages,
    int? inkColorArgb,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncState? syncState,
    int? version,
  }) {
    final nextPages = pages ?? this.pages;
    return Notebook(
      id: id,
      name: name ?? this.name,
      pages: nextPages,
      inkColorArgb: inkColorArgb ?? this.inkColorArgb,
      createdAt: createdAt,
      updatedAt:
          updatedAt ??
          (pages != null
              ? _latestActivity(createdAt, nextPages)
              : this.updatedAt),
      deletedAt: deletedAt ?? this.deletedAt,
      syncState: syncState ?? this.syncState,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Notebook &&
        other.id == id &&
        other.name == name &&
        _listEquals(other.pages, pages) &&
        other.inkColorArgb == inkColorArgb &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.deletedAt == deletedAt &&
        other.syncState == syncState &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(pages),
    inkColorArgb,
    createdAt,
    updatedAt,
    deletedAt,
    syncState,
    version,
  );
}

int _checkedPressure(int pressure) {
  if (pressure < 0 || pressure > maxPressure) {
    throw ArgumentError.value(pressure, 'pressure', 'must be 0..$maxPressure');
  }
  return pressure;
}

String _checkedName(String name) {
  if (name.isEmpty || name.length > maxNotebookNameLength) {
    throw ArgumentError.value(
      name,
      'name',
      'must be 1..$maxNotebookNameLength characters',
    );
  }
  return name;
}

DateTime _latestActivity(DateTime createdAt, List<NotebookPage> pages) {
  var latest = createdAt;
  for (final page in pages) {
    if (page.createdAt.isAfter(latest)) latest = page.createdAt;
    for (final stroke in page.strokes) {
      if (stroke.createdAt.isAfter(latest)) latest = stroke.createdAt;
    }
  }
  return latest;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
