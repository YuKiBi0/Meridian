import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/address.dart';
import '../../core/connection.dart';
import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// First-run page: one room address field and a Connect button (PRD CLI-01).
/// The room is looked up before joining it.
class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    required this.palette,
    required this.strings,
    required this.connection,
    required this.initial,
    required this.onConnect,
    required this.onQuit,
    this.initialError,
    this.onClose,
  });

  final Palette palette;
  final Strings strings;
  final ServerConnection connection;
  final String? initial;

  /// Why the user is here, e.g. the room was deleted.
  final String? initialError;

  /// Called with the address and the room's name once the room is found.
  final void Function(RoomAddress address, String roomName) onConnect;

  /// Back to the view; null when there is no room to go back to, and the
  /// header offers Quit instead.
  final VoidCallback? onClose;
  final VoidCallback onQuit;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  late String? _error = widget.initialError;
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_onConnection);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_onConnection);
    _controller.dispose();
    super.dispose();
  }

  void _onConnection() {
    if (!_trying) return;
    if (widget.connection.lastError != null && !widget.connection.everConnected) {
      setState(() {
        _trying = false;
        _error = widget.strings.cannotConnect;
      });
    }
  }

  Future<void> _submit() async {
    final s = widget.strings;
    final text = _controller.text;
    if (normalizeAddress(text) == null) {
      setState(() => _error = s.badAddress);
      return;
    }
    final address = RoomAddress.parse(text);
    if (address == null) {
      setState(() => _error = s.missingRoom);
      return;
    }
    setState(() {
      _error = null;
      _trying = true;
    });
    String? error;
    try {
      final name = await widget.connection.lookUpRoom(address);
      if (!mounted) return;
      widget.onConnect(address, name);
      return;
    } on RoomNotFound {
      error = s.roomNotFound;
    } catch (_) {
      error = s.cannotConnect;
    }
    if (!mounted) return;
    setState(() {
      _trying = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    return Panel(
      palette: p,
      title: s.appName,
      onClose: widget.onClose ?? widget.onQuit,
      closeLabel: widget.onClose == null ? s.quit : s.close,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.serverAddress, style: textStyle(12, p.fgMuted)),
          const SizedBox(height: 6),
          // Wraps, so a long address shows in full and can be checked.
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 3,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
            style: textStyle(14, p.fg),
            decoration: inputDecoration(p, s.addressHint),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(
            height: 44,
            child: _error == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_error!, style: textStyle(12, Palette.alert)),
                  ),
          ),
          const Spacer(),
          PrimaryButton(
            label: _trying ? s.connecting : s.connect,
            palette: p,
            onTap: _trying ? null : _submit,
          ),
        ]),
      ),
    );
  }
}
