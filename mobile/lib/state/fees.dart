class FeeState {
  final BigInt baseFee;
  final BigInt prioritySuggestion;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;
  final BigInt preVerificationGas;
  final BigInt verificationGasLimit;
  final BigInt callGasLimit;
  final BigInt bundlerFeeWei;
  const FeeState({
    required this.baseFee,
    required this.prioritySuggestion,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
    required this.preVerificationGas,
    required this.verificationGasLimit,
    required this.callGasLimit,
    required this.bundlerFeeWei,
  });

  BigInt get totalGas =>
      preVerificationGas + verificationGasLimit + callGasLimit;
  BigInt get networkFeeWei => totalGas * maxFeePerGas;
  BigInt get totalFeeWei => networkFeeWei + bundlerFeeWei;

  FeeState copyWith({
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    BigInt? bundlerFeeWei,
  }) =>
      FeeState(
        baseFee: baseFee,
        prioritySuggestion: prioritySuggestion,
        maxFeePerGas: maxFeePerGas ?? this.maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas ?? this.maxPriorityFeePerGas,
        preVerificationGas: preVerificationGas,
        verificationGasLimit: verificationGasLimit,
        callGasLimit: callGasLimit,
        bundlerFeeWei: bundlerFeeWei ?? this.bundlerFeeWei,
      );
}

String weiToEth(BigInt wei) => (wei / BigInt.from(10).pow(18)).toString();
String weiToGwei(BigInt wei) => (wei / BigInt.from(10).pow(9)).toString();
BigInt gweiToWei(String g) => BigInt.parse(g) * BigInt.from(10).pow(9);
