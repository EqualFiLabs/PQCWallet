import 'dart:typed_data';
import 'package:web3dart/crypto.dart' as w3;
import 'package:web3dart/web3dart.dart';

import '../crypto/mnemonic.dart';
import '../crypto/wots.dart';
import '../services/bundler_client.dart';
import '../services/rpc.dart';
import '../services/storage.dart';
import '../services/biometric.dart';
import '../services/entrypoint.dart';
import '../state/fees.dart';
import '../state/settings.dart';
import '../userop/userop.dart';
import '../userop/userop_signer.dart';

class UserOpFlow {
  final RpcClient rpc;
  final BundlerClient bundler;
  final PendingIndexStore store;

  UserOpFlow({required this.rpc, required this.bundler, required this.store});

  Future<String> sendEth({
    required Map<String, dynamic> cfg,
    required KeyMaterial keys,
    required EthereumAddress to,
    required BigInt amountWei,
    required AppSettings settings,
    required void Function(String) log,
    required Future<FeeState?> Function(FeeState) selectFees,
  }) async {
    final chainId = cfg['chainId'] as int;
    final wallet = EthereumAddress.fromHex(cfg['walletAddress']);
    final entryPoint = EthereumAddress.fromHex(cfg['entryPoint']);

    // view function encodings
    const fnNonce = ContractFunction('nonce', [],
        outputs: [FunctionParameter('', UintType())]);
    const fnCurrent = ContractFunction('currentPkCommit', [],
        outputs: [FunctionParameter('', FixedBytes(32))]);
    const fnNext = ContractFunction('nextPkCommit', [],
        outputs: [FunctionParameter('', FixedBytes(32))]);
    final dataNonce = fnNonce.encodeCall(const []);
    final dataCur = fnCurrent.encodeCall(const []);
    final dataNext = fnNext.encodeCall(const []);

    final nonceHex = await rpc.callViewHex(
        wallet.hex, '0x${w3.bytesToHex(dataNonce, include0x: false)}');
    final curHex = await rpc.callViewHex(
        wallet.hex, '0x${w3.bytesToHex(dataCur, include0x: false)}');
    final nextHex = await rpc.callViewHex(
        wallet.hex, '0x${w3.bytesToHex(dataNext, include0x: false)}');

    BigInt parseHexBigInt(String h) {
      final s = h.startsWith('0x') ? h.substring(2) : h;
      return s.isEmpty ? BigInt.zero : BigInt.parse(s, radix: 16);
    }

    Uint8List parseHex32(String h) {
      final b = w3.hexToBytes(h);
      if (b.length == 32) return Uint8List.fromList(b);
      if (b.length > 32) return Uint8List.fromList(b.sublist(b.length - 32));
      final out = Uint8List(32);
      out.setRange(32 - b.length, 32, b);
      return out;
    }

    final nonceOnChain = parseHexBigInt(nonceHex);
    final currentCommitOnChain = parseHex32(curHex);
    final nextCommitOnChain = parseHex32(nextHex);
    log('currentPkCommit: 0x${w3.bytesToHex(currentCommitOnChain, include0x: true)}');

    final pending = await store.load(chainId, wallet.hex);
    final callData = _encodeExecute(to, amountWei);

    final op = UserOperation()
      ..sender = wallet.hex
      ..nonce = nonceOnChain
      ..callData = callData;

    final gas = await bundler.estimateUserOpGas(op.toJson(), entryPoint.hex);
    op.callGasLimit = BigInt.parse(gas['callGasLimit'].toString());
    op.verificationGasLimit =
        BigInt.parse(gas['verificationGasLimit'].toString());
    op.preVerificationGas = BigInt.parse(gas['preVerificationGas'].toString());

    final fh = await rpc.feeHistory(5, [50]);
    final baseFees = (fh['baseFeePerGas'] as List)
        .map((h) => BigInt.parse(h.toString().substring(2), radix: 16))
        .toList();
    final baseFee = baseFees.isNotEmpty ? baseFees.last : BigInt.zero;

    BigInt priority = BigInt.zero;
    final rewards = fh['reward'] as List?;
    if (rewards != null && rewards.isNotEmpty) {
      final lastRewards = (rewards.last as List).cast<String>();
      if (lastRewards.isNotEmpty) {
        priority = BigInt.parse(lastRewards.first.substring(2), radix: 16);
      }
    }
    if (priority == BigInt.zero) {
      priority = await rpc.maxPriorityFeePerGas();
    }
    final suggestedMaxFee = baseFee + priority;

    var fees = FeeState(
      baseFee: baseFee,
      prioritySuggestion: priority,
      maxFeePerGas: suggestedMaxFee,
      maxPriorityFeePerGas: priority,
      preVerificationGas: op.preVerificationGas,
      verificationGasLimit: op.verificationGasLimit,
      callGasLimit: op.callGasLimit,
      bundlerFeeWei: BigInt.zero,
    );

    final chosen = await selectFees(fees);
    if (chosen == null) {
      throw Exception('fee-canceled');
    }
    fees = chosen;

    op.maxFeePerGas = fees.maxFeePerGas;
    op.maxPriorityFeePerGas = fees.maxPriorityFeePerGas;

    final ep = EntryPointService(rpc, entryPoint);
    final userOpHash = await ep.getUserOpHash(op);
    final userOpHashHex = '0x${w3.bytesToHex(userOpHash, include0x: false)}';

    final mustAuth = settings.requireBiometricForChain(chainId);
    if (mustAuth) {
      final bio = BiometricService();
      final can = await bio.canCheck();
      if (!can) {
        log('Biometric requested but unavailable. Aborting.');
        throw Exception('biometric-unavailable');
      }
      final ok = await bio.authenticate(
          reason: 'Authenticate to sign & send this transaction');
      if (!ok) {
        log('Authentication canceled/failed. Send aborted.');
        throw Exception('auth-failed');
      }
      log('Authentication successful.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    String decision;
    Map<String, dynamic>? record = pending;

    if (pending != null &&
        pending['userOpHash'] == userOpHashHex &&
        pending['index'] == nonceOnChain.toInt() &&
        (pending['entryPoint'] as String).toLowerCase() ==
            entryPoint.hex.toLowerCase() &&
        pending['networkChainId'] == chainId) {
      // reuse
      decision = 'reuse';
      op.signature =
          Uint8List.fromList(w3.hexToBytes(pending['signatureHybrid']));
      pending['status'] = 'sent';
      pending['lastAttemptAt'] = now;
      await store.save(chainId, wallet.hex, pending);
    } else {
      if (pending != null && pending['index'] != nonceOnChain.toInt()) {
        await store.clear(chainId, wallet.hex);
        decision = 'stale-clear';
      } else if (pending != null) {
        decision = 'rebuild';
      } else {
        decision = 'fresh';
      }

      // build new signature
      final creds = EthPrivateKey(Uint8List.fromList(keys.ecdsaPriv));
      final sigBytes = await creds.signToUint8List(userOpHash, chainId: null);
      final eSig = w3.MsgSignature(
        w3.bytesToInt(sigBytes.sublist(0, 32)),
        w3.bytesToInt(sigBytes.sublist(32, 64)),
        sigBytes[64],
      );

      final index = nonceOnChain.toInt();
      final seedI = hkdfIndex(Uint8List.fromList(keys.wotsMaster), index);
      final (sk, pk) = Wots.keygen(seedI);
      final wSig = Wots.sign(userOpHash, sk);

      final confirmCommit = nextCommitOnChain;
      final nextNextSeed =
          hkdfIndex(Uint8List.fromList(keys.wotsMaster), index + 2);
      final (_, nextNextPk) = Wots.keygen(nextNextSeed);
      final proposeCommit = Wots.commitPk(nextNextPk);

      op.signature =
          packHybridSignature(eSig, wSig, pk, confirmCommit, proposeCommit);

      final pkBytes = pk.expand((e) => e).toList();
      record = {
        'version': 1,
        'wallet': wallet.hex,
        'entryPoint': entryPoint.hex,
        'networkChainId': chainId,
        'userOpHash': userOpHashHex,
        'nonce': nonceOnChain.toString(),
        'index': index,
        'signatureHybrid': '0x${w3.bytesToHex(op.signature, include0x: false)}',
        'confirmNextCommit':
            '0x${w3.bytesToHex(confirmCommit, include0x: false)}',
        'proposeNextCommit':
            '0x${w3.bytesToHex(proposeCommit, include0x: false)}',
        'wotsPk': '0x${w3.bytesToHex(pkBytes, include0x: false)}',
        'status': 'pending',
        'createdAt': now,
        'lastAttemptAt': now,
      };
      if (pending != null && decision == 'rebuild') {
        record['createdAt'] = pending['createdAt'];
      }
      await store.save(chainId, wallet.hex, record);
    }

    final pendingStatus = pending == null ? 'absent' : 'present';
    log([
      'pendingIndex: $pendingStatus',
      'nonce(): ${nonceOnChain.toString()}',
      'userOpHash(draft): ${userOpHashHex.substring(0, 10)}',
      'decision: $decision',
    ].join('\n'));

    final uoh = await bundler.sendUserOperation(op.toJson(), entryPoint.hex);
    record ??= await store.load(chainId, wallet.hex);
    if (record != null) {
      record['status'] = 'sent';
      record['lastAttemptAt'] = now;
      await store.save(chainId, wallet.hex, record);
    }
    return uoh;
  }

  Uint8List _encodeExecute(EthereumAddress to, BigInt value) {
    const execute = ContractFunction('execute', [
      FunctionParameter('to', AddressType()),
      FunctionParameter('value', UintType()),
      FunctionParameter('data', DynamicBytes()),
    ]);
    return execute.encodeCall([to, value, Uint8List(0)]);
  }
}
