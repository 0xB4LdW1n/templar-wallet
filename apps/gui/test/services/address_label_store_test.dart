// An address's mark is a label and a colour, kept together on this device.
// An address is grey until the user picks a colour; the pick survives a
// restart, and picking grey is picking nothing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/services/address_label_store.dart';

const _a = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
const _b = 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a';

void main() {
  final store = AddressLabelStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.debugReset();
  });

  test('an unmarked address is grey', () {
    expect(AddressLabelStore.greyHue, AddressLabelStore.hueCount - 1);
    expect(store.hueFor(_a), AddressLabelStore.greyHue);
    expect(store.hueFor(_b), AddressLabelStore.greyHue);
    expect(store.pickedHueFor(_a), isNull);
    expect(store.labelFor(_a), isNull);
  });

  test('picking grey is picking no colour: nothing is stored', () async {
    await store.setMark(_a, label: 'Rent', hue: 1);
    await store.setMark(_a, label: 'Rent', hue: AddressLabelStore.greyHue);
    expect(store.pickedHueFor(_a), isNull);
    expect(store.hueFor(_a), AddressLabelStore.greyHue);
    expect(store.labelFor(_a), 'Rent');
  });

  test('a label and a colour are written and read back together', () async {
    await store.setMark(_a, label: '  Savings ', hue: 3);
    expect(store.labelFor(_a), 'Savings');
    expect(store.pickedHueFor(_a), 3);
    expect(store.hueFor(_a), 3);

    // A restart: what was written is what is read.
    store.debugReset();
    await store.load();
    expect(store.labelFor(_a), 'Savings');
    expect(store.hueFor(_a), 3);
  });

  test('renaming keeps the colour; clearing both goes back to grey', () async {
    await store.setMark(_a, label: 'Rent', hue: 4);
    await store.setLabel(_a, 'Rent, October');
    expect(store.labelFor(_a), 'Rent, October');
    expect(store.hueFor(_a), 4);

    await store.setMark(_a, label: '', hue: null);
    expect(store.labelFor(_a), isNull);
    expect(store.pickedHueFor(_a), isNull);
    expect(store.hueFor(_a), AddressLabelStore.greyHue);
  });

  test('a colour can be picked for an address with no label', () async {
    await store.setMark(_b, label: '', hue: 1);
    expect(store.labelFor(_b), isNull);
    expect(store.hueFor(_b), 1);
  });

  test('labels written before colours existed still read', () async {
    SharedPreferences.setMockInitialValues({
      'address_labels_v1': json.encode({_a: 'Savings'}),
    });
    store.debugReset();
    await store.load();
    expect(store.labelFor(_a), 'Savings');
    expect(store.hueFor(_a), AddressLabelStore.greyHue);
  });

  test('a write notifies, and a write that changes nothing does not', () async {
    var notified = 0;
    void listener() => notified++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    await store.load();
    notified = 0;

    await store.setMark(_a, label: 'Savings', hue: 2);
    expect(notified, 1);
    await store.setMark(_a, label: 'Savings', hue: 2);
    expect(notified, 1);
  });
}
