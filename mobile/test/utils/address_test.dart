import 'package:flutter_test/flutter_test.dart';

import 'package:pqc_wallet/utils/address.dart';

void main() {
  group('truncateAddress', () {
    test('returns address when short enough', () {
      const address = '0x123456';
      expect(truncateAddress(address), address);
    });

    test('truncates address with ellipsis when long', () {
      const address = '0x1234567890ABCDEF';
      expect(truncateAddress(address), '0x1234...CDEF');
    });
  });
}
