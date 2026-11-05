// Adapted from flutter_settings_screens 0.3.4 (lib/src/cache/cache_provider_impl.dart).
//
// MIT License
//
// Copyright (c) 2019 Harshvardhan Joshi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [CacheProvider] מעל shared_preferences — נסיגה כשפתיחת [HiveCache] נכשלת.
class SharePreferenceCache extends CacheProvider {
  SharedPreferences? _preferences;

  @override
  Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    _preferences = await SharedPreferences.getInstance();
  }

  @override
  bool? getBool(String key, {bool? defaultValue}) => _preferences?.getBool(key);

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _preferences?.getDouble(key);

  @override
  int? getInt(String key, {int? defaultValue}) => _preferences?.getInt(key);

  @override
  String? getString(String key, {String? defaultValue}) =>
      _preferences?.getString(key);

  @override
  Future<void> setBool(String key, bool? value) async {
    await _preferences?.setBool(key, value ?? false);
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    await _preferences?.setDouble(key, value!);
  }

  @override
  Future<void> setInt(String key, int? value) async {
    await _preferences?.setInt(key, value!);
  }

  @override
  Future<void> setString(String key, String? value) async {
    await _preferences?.setString(key, value!);
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (T == int || value is int) {
      await _preferences?.setInt(key, value as int);
    } else if (T == double || value is double) {
      await _preferences?.setDouble(key, value as double);
    } else if (T == bool || value is bool) {
      await _preferences?.setBool(key, value as bool);
    } else if (T == String || value is String) {
      await _preferences?.setString(key, value as String);
    } else {
      throw Exception('SharePreferenceCache cannot store type $T');
    }
  }

  @override
  bool containsKey(String key) => _preferences?.containsKey(key) ?? false;

  @override
  Set getKeys() => _preferences?.getKeys() ?? {};

  @override
  Future<void> remove(String key) async {
    if (containsKey(key)) {
      await _preferences?.remove(key);
    }
  }

  @override
  Future<void> removeAll() async {
    await _preferences?.clear();
  }

  /// כמו `HiveCache.getValue`: הערך השמור אם הוא מסוג [T] (גם `bool?` וכו'),
  /// אחרת [defaultValue].
  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _preferences?.get(key);
    return value is T ? value : defaultValue;
  }
}
