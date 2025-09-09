import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/contracts.dart'
    show
        ContractFunction,
        FunctionParameter,
        UintType,
        FixedBytes,
        AddressType,
        DynamicBytes,
        TupleType;
import 'package:web3dart/crypto.dart' as w3;

import 'theme/theme.dart';
import 'services/rpc.dart';
import 'services/bundler_client.dart';
import 'crypto/mnemonic.dart';
import 'crypto/wots.dart';
import 'userop/userop.dart';
import 'userop/userop_signer.dart';

void main() => runApp(const PQCApp());

class PQCApp extends StatefulWidget {
  const PQCApp({super.key});
  @override
  State<PQCApp> createState() => _PQCAppState();
}

class _PQCAppState extends State<PQCApp> {
  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final storage = const FlutterSecureStorage();
  KeyMaterial? _keys;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    _load();
  }

  Future<void> _load() async {
    final cfg =
        jsonDecode(await rootBundle.loadString('assets/config.example.json'))
            as Map<String, dynamic>;
    setState(() => _cfg = cfg);
    // Load or create mnemonic
    final existing = await storage.read(key: 'mnemonic');
    final km = deriveFromMnemonic(existing);
    if (existing == null)
      await storage.write(key: 'mnemonic', value: km.mnemonic);
    setState(() => _keys = km);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('EqualFi PQC Wallet (MVP)')),
        body: _cfg == null || _keys == null
            ? const Center(child: CircularProgressIndicator())
            : _Body(
                cfg: _cfg!,
                keys: _keys!,
                setStatus: (s) => setState(() => _status = s)),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(12),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final KeyMaterial keys;
  final void Function(String) setStatus;
  const _Body({required this.cfg, required this.keys, required this.setStatus});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final rpc = RpcClient(widget.cfg['rpcUrl']);
  late final bundler = BundlerClient(widget.cfg['bundlerUrl']);
  final recipientCtl = TextEditingController();
  final amountCtl = TextEditingController(text: '0.001');

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(child: SelectableText('ChainId: ${widget.cfg['chainId']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('Wallet: ${widget.cfg['walletAddress']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('EntryPoint: ${widget.cfg['entryPoint']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('Aggregator: ${widget.cfg['aggregator']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('ProverRegistry: ${widget.cfg['proverRegistry']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('ForceOnChainVerify: ${widget.cfg['forceOnChainVerify']}')),
        const SizedBox(height: 16),
        TextField(
            controller: recipientCtl,
            decoration: const InputDecoration(hintText: 'Recipient (0x...)')),
        const SizedBox(height: 8),
        TextField(
            controller: amountCtl,
            decoration: const InputDecoration(hintText: 'Amount ETH')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: _sendEth, child: const Text('Send ETH (PQC)'))),
          ],
        ),
      ],
    );
  }

  Future<void> _sendEth() async {
    try {
      widget.setStatus('Reading wallet state...');
      final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
      final entryPoint = EthereumAddress.fromHex(widget.cfg['entryPoint']);
      final to = EthereumAddress.fromHex(recipientCtl.text.trim());
      final amountWei =
          EtherAmount.fromBase10String(EtherUnit.ether, amountCtl.text.trim())
              .getInWei;

      // 0) Prepare function ABIs for view calls
      const fnNonce = ContractFunction(
        'nonce',
        [],
        outputs: [FunctionParameter('', UintType())],
      );

      const fnCurrent = ContractFunction(
        'currentPkCommit',
        [],
        outputs: [FunctionParameter('', FixedBytes(32))],
      );

      const fnNext = ContractFunction(
        'nextPkCommit',
        [],
        outputs: [FunctionParameter('', FixedBytes(32))],
      );

      final dataNonce = fnNonce.encodeCall(const []);
      final dataCur = fnCurrent.encodeCall(const []);
      final dataNext = fnNext.encodeCall(const []);

      // 1) Read on-chain state via eth_call
      final nonceHex = await rpc.callViewHex(
        wallet.hex,
        '0x${w3.bytesToHex(dataNonce, include0x: false)}',
      );
      final curHex = await rpc.callViewHex(
        wallet.hex,
        '0x${w3.bytesToHex(dataCur, include0x: false)}',
      );
      final nextHex = await rpc.callViewHex(
        wallet.hex,
        '0x${w3.bytesToHex(dataNext, include0x: false)}',
      );

      // 2) Decode results
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

      // 3) Log the reads to the UI
      widget.setStatus([
        'Read wallet state:',
        '- nonce: ${nonceOnChain.toString()}',
        '- currentPkCommit: ${w3.bytesToHex(currentCommitOnChain, include0x: true)}',
        '- nextPkCommit: ${w3.bytesToHex(nextCommitOnChain, include0x: true)}',
      ].join('\n'));

      // 4) Prepare callData as before
      const execute = ContractFunction('execute', [
        FunctionParameter('to', AddressType()),
        FunctionParameter('value', UintType()),
        FunctionParameter('data', DynamicBytes()),
      ]);
      final callData = execute.encodeCall([to, amountWei, Uint8List(0)]);

      // 5) Build userOp with real nonce
      final op = UserOperation()
        ..sender = wallet.hex
        ..nonce = nonceOnChain
        ..callData = callData;

      // 6) Estimate gas via bundler
      final gas = await bundler.estimateUserOpGas(op.toJson(), entryPoint.hex);
      op.callGasLimit = BigInt.parse(gas['callGasLimit'].toString());
      op.verificationGasLimit =
          BigInt.parse(gas['verificationGasLimit'].toString());
      op.preVerificationGas =
          BigInt.parse(gas['preVerificationGas'].toString());

      // 7) Get userOpHash from EntryPoint via eth_call
      final userOpHash = await _getUserOpHash(entryPoint.hex, op);
      // ECDSA sign
      final creds = EthPrivateKey(Uint8List.fromList(widget.keys.ecdsaPriv));
      final sigBytes = await creds.signToUint8List(userOpHash,
          chainId: null); // raw 32-byte hash
      final eSig = w3.MsgSignature(
        w3.bytesToInt(sigBytes.sublist(0, 32)),
        w3.bytesToInt(sigBytes.sublist(32, 64)),
        sigBytes[64],
      );

      // 8) WOTS indices/keys anchored to nonce()
      final index = nonceOnChain.toInt();
      final seedI =
          hkdfIndex(Uint8List.fromList(widget.keys.wotsMaster), index);
      final (sk, pk) = Wots.keygen(seedI);
      final wSig = Wots.sign(userOpHash, sk);

      // We DO NOT recompute confirm for "next"; we confirm on-chain next
      final confirmCommit = nextCommitOnChain;

      // propose commitment for index+2
      final nextNextSeed =
          hkdfIndex(Uint8List.fromList(widget.keys.wotsMaster), index + 2);
      final (_, nextNextPk) = Wots.keygen(nextNextSeed);
      final proposeCommit = Wots.commitPk(nextNextPk);

      // 9) Pack hybrid signature
      op.signature =
          packHybridSignature(eSig, wSig, pk, confirmCommit, proposeCommit);

      widget.setStatus('Submitting to bundler...');
      final uoh = await bundler.sendUserOperation(op.toJson(), entryPoint.hex);
      widget.setStatus('Sent. UserOpHash: $uoh (waiting for receipt...)');

      // Poll for receipt
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final r = await bundler.getUserOperationReceipt(uoh);
        if (r != null) {
          widget
              .setStatus('Inclusion tx: ${r['receipt']['transactionHash']} ✅');
          return;
        }
      }
      widget.setStatus('Timed out waiting for receipt (check explorer).');
    } catch (e) {
      widget.setStatus('Error: $e');
    }
  }

  Future<Uint8List> _getUserOpHash(String entryPoint, UserOperation op) async {
    // Solidity selector: getUserOpHash((...))
    const userOpType = TupleType([
      AddressType(),
      UintType(),
      DynamicBytes(),
      DynamicBytes(),
      UintType(),
      UintType(),
      UintType(),
      UintType(),
      UintType(),
      DynamicBytes(),
      DynamicBytes(),
    ]);
    const getUserOpHashFn = ContractFunction(
      'getUserOpHash',
      [FunctionParameter('op', userOpType)],
      outputs: [FunctionParameter('', FixedBytes(32))],
    );
    final data = getUserOpHashFn.encodeCall([
      [
        EthereumAddress.fromHex(op.sender),
        op.nonce,
        op.initCode,
        op.callData,
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        op.paymasterAndData,
        Uint8List(0),
      ]
    ]);
    final payload = {
      'to': entryPoint,
      'data': '0x${w3.bytesToHex(data, include0x: false)}'
    };
    final res = await RpcClient(widget.cfg['rpcUrl'])
        .call('eth_call', [payload, 'latest']);
    return Uint8List.fromList(w3.hexToBytes(res.toString()));
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0x2211CDEF),
          borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
