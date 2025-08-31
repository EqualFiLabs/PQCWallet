import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:web3dart/web3dart.dart';
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
  BigInt _nonce = BigInt.zero;

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    _load();
  }

  Future<void> _load() async {
    final cfg = jsonDecode(await rootBundle.loadString('assets/config.example.json')) as Map<String, dynamic>;
    setState(() => _cfg = cfg);
    // Load or create mnemonic
    final existing = await storage.read(key: 'mnemonic');
    final km = deriveFromMnemonic(existing);
    if (existing == null) await storage.write(key: 'mnemonic', value: km.mnemonic);
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
            : _Body(cfg: _cfg!, keys: _keys!, setStatus: (s) => setState(() => _status = s)),
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
        _Card(child: SelectableText('Wallet: ${widget.cfg['walletAddress']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('EntryPoint: ${widget.cfg['entryPoint']}')),
        const SizedBox(height: 16),
        TextField(controller: recipientCtl, decoration: const InputDecoration(hintText: 'Recipient (0x...)')),
        const SizedBox(height: 8),
        TextField(controller: amountCtl, decoration: const InputDecoration(hintText: 'Amount ETH')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: ElevatedButton(onPressed: _sendEth, child: const Text('Send ETH (PQC)'))),
          ],
        ),
      ],
    );
  }

  Future<void> _sendEth() async {
    try {
      widget.setStatus('Building UserOp...');
      final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
      final entryPoint = EthereumAddress.fromHex(widget.cfg['entryPoint']);
      final to = EthereumAddress.fromHex(recipientCtl.text.trim());
      final amountWei = EtherAmount.fromUnitAndValue(EtherUnit.ether, amountCtl.text.trim()).getInWei;

      // callData = PQCWallet.execute(to, value, data="")
      final executeSelector = w3.keccakUtf8('execute(address,uint256,bytes)').sublist(0, 4);
      final enc = BytesBuilder();
      enc.add(executeSelector);
      enc.add(w3.abiEncode(['address','uint256','bytes'], [to, amountWei, Uint8List(0)]));
      final callData = enc.toBytes();

      // Build userOp (gas fields filled after estimate)
      final op = UserOperation()
        ..sender = wallet.hex
        ..nonce = BigInt.zero
        ..callData = callData;

      // Estimate gas via bundler
      final gas = await bundler.estimateUserOpGas(op.toJson(), entryPoint.hex);
      op.callGasLimit = BigInt.parse(gas['callGasLimit'].toString());
      op.verificationGasLimit = BigInt.parse(gas['verificationGasLimit'].toString());
      op.preVerificationGas = BigInt.parse(gas['preVerificationGas'].toString());

      // Get userOpHash from EntryPoint via eth_call
      final userOpHash = await _getUserOpHash(entryPoint.hex, op);
      // ECDSA sign
      final creds = EthPrivateKey(widget.keys.ecdsaPriv);
      final eSig = await creds.sign(userOpHash, chainId: null); // raw 32-byte hash
      // WOTS sign/commit/nextCommit
      final index = 0; // MVP demo uses nonce 0; in production track wallet.nonce via RPC
      final seedI = hkdfIndex(Uint8List.fromList(widget.keys.wotsMaster), index);
      final (sk, pk) = Wots.keygen(seedI);
      final wSig = Wots.sign(userOpHash, sk);
      final nextSeed = hkdfIndex(Uint8List.fromList(widget.keys.wotsMaster), index + 1);
      final (_, nextPk) = Wots.keygen(nextSeed);
      final nextCommit = Wots.commitPk(nextPk);

      // Pack signature
      op.signature = packHybridSignature(eSig, wSig, pk, nextCommit);

      widget.setStatus('Submitting to bundler...');
      final uoh = await bundler.sendUserOperation(op.toJson(), entryPoint.hex);
      widget.setStatus('Sent. UserOpHash: $uoh (waiting for receipt...)');

      // Poll for receipt
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final r = await bundler.getUserOperationReceipt(uoh);
        if (r != null) {
          widget.setStatus('Inclusion tx: ${r['receipt']['transactionHash']} ✅');
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
    final data = w3.hexToBytes('0x' +
      w3.bytesToHex(w3.keccakUtf8('getUserOpHash((address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes))').sublist(0,4), include0x:false) +
      w3.bytesToHex(
        w3.abiEncode(
          [
            '(address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes)'
          ],
          [[
            op.sender,
            op.nonce,
            op.initCode,
            op.callData,
            op.callGasLimit,
            op.verificationGasLimit,
            op.preVerificationGas,
            op.maxFeePerGas,
            op.maxPriorityFeePerGas,
            op.paymasterAndData,
            Uint8List(0) // signature ignored by getUserOpHash
          ]],
        ),
        include0x:false
      )
    );
    final payload = {
      'to': entryPoint,
      'data': '0x${w3.bytesToHex(data, include0x:false)}'
    };
    final res = await RpcClient(widget.cfg['rpcUrl']).call('eth_call', [payload, 'latest']);
    return Uint8List.fromList(w3.hexToBytes(res.toString()));
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0x2211CDEF), borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
