import 'dart:collection';

/// An immutable, sparse list with stable logical indices and shared chunks.
class ChunkedList<T> extends ListBase<T> {
  static const int chunkLength = 256;
  static const int _chunkShift = 8;
  static const int _chunkMask = chunkLength - 1;

  final int _length;
  final T defaultValue;
  final Map<int, _Chunk<T>> _chunks;

  ChunkedList._(this._length, this.defaultValue, this._chunks);

  factory ChunkedList.filled(int length, T defaultValue) {
    RangeError.checkNotNegative(length, 'length');
    return ChunkedList._(length, defaultValue, <int, _Chunk<T>>{});
  }

  factory ChunkedList.from(List<T> values, {required T defaultValue}) {
    if (values is ChunkedList<T> && values.defaultValue == defaultValue) {
      return values;
    }
    final editor = ChunkedList<T>.filled(values.length, defaultValue).edit();
    editor.setRangeValues(0, values);
    return editor.build();
  }

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('ChunkedList is immutable');

  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    final chunk = _chunks[index >> _chunkShift];
    return chunk == null ? defaultValue : chunk.values[index & _chunkMask];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('ChunkedList is immutable');

  @override
  Iterator<T> get iterator => _ChunkedIterator(this);

  /// Visits resident non-default values in logical index order.
  Iterable<T> get nonDefaultValues sync* {
    final indices = _chunks.keys.toList()..sort();
    for (final chunkIndex in indices) {
      final values = _chunks[chunkIndex]!.values;
      final start = chunkIndex << _chunkShift;
      final available = _length - start;
      final count = available < chunkLength ? available : chunkLength;
      for (var offset = 0; offset < count; offset++) {
        final value = values[offset];
        if (value != defaultValue) yield value;
      }
    }
  }

  ChunkedListEditor<T> edit() => ChunkedListEditor._(this);

  /// Keeps logical length while clearing values outside the half-open range.
  ChunkedList<T> retainRange(int start, int end) {
    final editor = edit()..retainRange(start, end);
    return editor.build();
  }
}

/// A single-use editor; each touched chunk is copied at most once per edit.
class ChunkedListEditor<T> extends ListBase<T> {
  final ChunkedList<T> _source;
  Map<int, _Chunk<T>>? _editedChunks;
  final Set<int> _ownedChunks = {};
  int _length;
  bool _changed = false;
  bool _built = false;

  ChunkedListEditor._(this._source) : _length = _source.length;

  bool get changed => _changed;

  Map<int, _Chunk<T>> get _chunks => _editedChunks ?? _source._chunks;

  void _checkOpen() {
    if (_built) throw StateError('This ChunkedList editor has been built');
  }

  Map<int, _Chunk<T>> _writableDirectory() =>
      _editedChunks ??= Map<int, _Chunk<T>>.of(_source._chunks);

  _Chunk<T> _writableChunk(int chunkIndex) {
    final chunks = _writableDirectory();
    if (_ownedChunks.add(chunkIndex)) {
      final existing = chunks[chunkIndex];
      chunks[chunkIndex] = existing == null
          ? _Chunk(
              List<T>.filled(ChunkedList.chunkLength, _source.defaultValue),
              0,
            )
          : _Chunk(
              List<T>.of(existing.values, growable: false),
              existing.count,
            );
    }
    return chunks[chunkIndex]!;
  }

  @override
  int get length => _length;

  @override
  set length(int value) {
    _checkOpen();
    RangeError.checkNotNegative(value, 'length');
    if (value == _length) return;
    if (value < _length) retainRange(0, value);
    _length = value;
    _changed = true;
  }

  @override
  T operator [](int index) {
    _checkOpen();
    RangeError.checkValidIndex(index, this, 'index', _length);
    final chunk = _chunks[index >> ChunkedList._chunkShift];
    return chunk == null
        ? _source.defaultValue
        : chunk.values[index & ChunkedList._chunkMask];
  }

  @override
  void operator []=(int index, T value) {
    _checkOpen();
    RangeError.checkValidIndex(index, this, 'index', _length);
    final chunkIndex = index >> ChunkedList._chunkShift;
    final offset = index & ChunkedList._chunkMask;
    final previous = _chunks[chunkIndex];
    final oldValue = previous == null
        ? _source.defaultValue
        : previous.values[offset];
    if (oldValue == value) return;
    final chunk = _writableChunk(chunkIndex);
    if (oldValue == _source.defaultValue) chunk.count++;
    if (value == _source.defaultValue) chunk.count--;
    chunk.values[offset] = value;
    if (chunk.count == 0) {
      _writableDirectory().remove(chunkIndex);
      _ownedChunks.remove(chunkIndex);
    }
    _changed = true;
  }

  void setRangeValues(int start, List<T> values) =>
      setRange(start, start + values.length, values);

  @override
  void setRange(int start, int end, Iterable<T> iterable, [int skipCount = 0]) {
    _checkOpen();
    RangeError.checkValidRange(start, end, _length);
    final count = end - start;
    if (count == 0) return;
    RangeError.checkNotNegative(skipCount, 'skipCount');

    final List<T> values;
    var sourceIndex = skipCount;
    if (iterable is List<T> && !identical(iterable, this)) {
      values = iterable;
    } else {
      // Snapshot aliased/iterable input before any destination writes.
      values = iterable.skip(skipCount).take(count).toList(growable: false);
      sourceIndex = 0;
    }
    if (sourceIndex + count > values.length) {
      throw StateError('Too few elements');
    }

    final defaultValue = _source.defaultValue;
    var index = start;
    while (index < end) {
      final chunkIndex = index >> ChunkedList._chunkShift;
      final offset = index & ChunkedList._chunkMask;
      final available = ChunkedList.chunkLength - offset;
      final count = end - index < available ? end - index : available;
      final existing = _chunks[chunkIndex];
      var firstChange = 0;
      while (firstChange < count &&
          (existing == null
                  ? defaultValue
                  : existing.values[offset + firstChange]) ==
              values[sourceIndex + firstChange]) {
        firstChange++;
      }
      if (firstChange < count) {
        final chunk = _writableChunk(chunkIndex);
        for (var item = firstChange; item < count; item++) {
          final oldValue = chunk.values[offset + item];
          final value = values[sourceIndex + item];
          if (oldValue == value) continue;
          if (oldValue == defaultValue) chunk.count++;
          if (value == defaultValue) chunk.count--;
          chunk.values[offset + item] = value;
        }
        if (chunk.count == 0) {
          _writableDirectory().remove(chunkIndex);
          _ownedChunks.remove(chunkIndex);
        }
        _changed = true;
      }
      index += count;
      sourceIndex += count;
    }
  }

  @override
  void fillRange(int start, int end, [T? fill]) {
    _checkOpen();
    RangeError.checkValidRange(start, end, _length);
    final value = fill as T;
    final defaultValue = _source.defaultValue;
    var index = start;
    while (index < end) {
      final chunkIndex = index >> ChunkedList._chunkShift;
      final offset = index & ChunkedList._chunkMask;
      final available = ChunkedList.chunkLength - offset;
      final count = end - index < available ? end - index : available;
      final existing = _chunks[chunkIndex];
      if (value == defaultValue &&
          (existing == null ||
              (offset == 0 && count == ChunkedList.chunkLength))) {
        if (existing != null) {
          _writableDirectory().remove(chunkIndex);
          _ownedChunks.remove(chunkIndex);
          _changed = true;
        }
      } else {
        var firstChange = 0;
        while (firstChange < count &&
            (existing == null
                    ? defaultValue
                    : existing.values[offset + firstChange]) ==
                value) {
          firstChange++;
        }
        if (firstChange < count) {
          final chunk = _writableChunk(chunkIndex);
          for (var item = firstChange; item < count; item++) {
            final oldValue = chunk.values[offset + item];
            if (oldValue == value) continue;
            if (oldValue == defaultValue) chunk.count++;
            if (value == defaultValue) chunk.count--;
            chunk.values[offset + item] = value;
          }
          if (chunk.count == 0) {
            _writableDirectory().remove(chunkIndex);
            _ownedChunks.remove(chunkIndex);
          }
          _changed = true;
        }
      }
      index += count;
    }
  }

  void retainRange(int start, int end) {
    _checkOpen();
    RangeError.checkValidRange(start, end, _length);
    for (final chunkIndex in _chunks.keys.toList(growable: false)) {
      final chunkStart = chunkIndex << ChunkedList._chunkShift;
      final chunkEnd = chunkStart + ChunkedList.chunkLength;
      if (chunkEnd <= start || chunkStart >= end) {
        _writableDirectory().remove(chunkIndex);
        _ownedChunks.remove(chunkIndex);
        _changed = true;
      } else if (chunkStart < start || chunkEnd > end) {
        final first = chunkStart;
        final last = chunkEnd < _length ? chunkEnd : _length;
        for (var index = first; index < last; index++) {
          if (index < start || index >= end) {
            this[index] = _source.defaultValue;
          }
        }
      }
    }
  }

  ChunkedList<T> build() {
    _checkOpen();
    _built = true;
    return _changed
        ? ChunkedList._(_length, _source.defaultValue, _chunks)
        : _source;
  }
}

class _Chunk<T> {
  final List<T> values;
  int count;

  _Chunk(this.values, this.count);
}

class _ChunkedIterator<T> implements Iterator<T> {
  final ChunkedList<T> _list;
  int _index = -1;
  _Chunk<T>? _chunk;
  T? _current;

  _ChunkedIterator(this._list);

  @override
  T get current => _current as T;

  @override
  bool moveNext() {
    if (++_index >= _list.length) {
      _current = null;
      return false;
    }
    final offset = _index & ChunkedList._chunkMask;
    if (offset == 0) _chunk = _list._chunks[_index >> ChunkedList._chunkShift];
    _current = _chunk == null ? _list.defaultValue : _chunk!.values[offset];
    return true;
  }
}
