String truncateAddress(String address) {
  if (address.length <= 10) {
    return address;
  }
  final start = address.substring(0, 6);
  final end = address.substring(address.length - 4);
  return '$start...$end';
}
