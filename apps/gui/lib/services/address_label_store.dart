import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mark a user gives one of their own receive addresses: a label
/// ("Rent", "Exchange withdrawal") and a colour, kept on this device.
///
/// Display metadata only: the engine neither reads nor needs it. Keyed by
/// the address itself, which is unique across wallets and chains, so a mark
/// follows its address wherever the address is listed — Receive, the coin
/// wall's trays, the coin list, Send's own-address picker. A listenable, so
/// every row showing an address redraws when its mark changes.
///
/// The colour is an index into the app's tag hues (`AppScheme.series`), not
/// a colour value: the same pick reads right in the dark and the light
/// theme. An address is grey ([greyHue]) until the user picks a colour, so
/// colour on screen always means someone chose it; the same address is the
/// same colour on Receive, on the coin wall and in a picker.
class AddressLabelStore extends ChangeNotifier {
  AddressLabelStore._();
  static final AddressLabelStore instance = AddressLabelStore._();

  static const _key = 'address_labels_v1';
  static const _hueKey = 'address_label_hues_v1';

  /// Longest label kept. A label is a few words, not a note.
  static const int maxLength = 40;

  /// How many hues a mark can pick from (the length of `AppScheme.series`).
  static const int hueCount = 6;

  /// The hue of an address nobody coloured: grey (slate, the last tag hue).
  /// Picking it is picking no colour, so it is never stored.
  static const int greyHue = hueCount - 1;

  Map<String, String>? _labels;
  Map<String, int>? _hues;

  /// Reads the marks once; later calls are free. Rows may render before
  /// this lands — they show the engine's label until it does.
  Future<void> load() async {
    if (_labels != null && _hues != null) return;
    var labels = <String, String>{};
    var hues = <String, int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        labels = {
          for (final e in decoded.entries)
            if (e.value is String) e.key: e.value as String,
        };
      }
      final rawHues = prefs.getString(_hueKey);
      if (rawHues != null) {
        final decoded = jsonDecode(rawHues) as Map<String, dynamic>;
        hues = {
          for (final e in decoded.entries)
            if (e.value is int &&
                (e.value as int) >= 0 &&
                (e.value as int) % hueCount != greyHue)
              e.key: (e.value as int) % hueCount,
        };
      }
    } catch (_) {
      // Unreadable preferences are no marks, not a crash on Receive.
      labels = {};
      hues = {};
    }
    // A write may have raced the read: what was set in memory wins.
    _labels = {...labels, ...?_labels};
    _hues = {...hues, ...?_hues};
    notifyListeners();
  }

  /// The user's label for [address], or null when they gave none.
  String? labelFor(String address) => _labels?[address];

  /// The hue the user picked for [address] (an index into the tag hues), or
  /// null when they picked none.
  int? pickedHueFor(String address) => _hues?[address];

  /// The hue [address] is drawn in: the user's pick, else grey.
  int hueFor(String address) => pickedHueFor(address) ?? greyHue;

  /// Sets the label of [address]; an empty one removes it. The colour is
  /// left as it is.
  Future<void> setLabel(String address, String label) =>
      setMark(address, label: label, hue: pickedHueFor(address));

  /// Sets the label and the colour of [address] in one write. An empty
  /// label removes the label; a null [hue], or [greyHue], removes the pick
  /// (the address goes back to grey).
  Future<void> setMark(
    String address, {
    required String label,
    required int? hue,
  }) async {
    await load();
    final labels = _labels!;
    final hues = _hues!;
    final text = label.trim();
    final clipped = text.length > maxLength
        ? text.substring(0, maxLength)
        : text;
    final picked = hue == null || hue % hueCount == greyHue
        ? null
        : hue % hueCount;

    var changed = false;
    if (clipped.isEmpty) {
      changed = labels.remove(address) != null || changed;
    } else if (labels[address] != clipped) {
      labels[address] = clipped;
      changed = true;
    }
    if (picked == null) {
      changed = hues.remove(address) != null || changed;
    } else if (hues[address] != picked) {
      hues[address] = picked;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(labels));
    await prefs.setString(_hueKey, jsonEncode(hues));
  }

  /// Forgets what was read, so the next [load] reads again. Tests only.
  @visibleForTesting
  void debugReset() {
    _labels = null;
    _hues = null;
  }
}
