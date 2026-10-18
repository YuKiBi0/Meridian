import 'package:flutter/material.dart';

import '../../core/address.dart';
import '../../core/connection.dart';
import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// First-run page: one address field and a Connect button (PRD CLI-01).
class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    required this.palette,
    required this.strings,
    required this.connection,
    required this.initial,
    required this.onConnect,
    this.onClose,
  });

  final Palette palette;
  final Strings strings;
  final ServerConnection connection;
  final String? initial;

  /// Called with the normalized address when the user asks to connect.
  final ValueChanged<Uri> onConnect;
  final VoidCallback? onClose;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  String? _error;
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

  void _submit() {
    final uri = normalizeAddress(_controller.text);
    if (uri == null) {
      setState(() => _error = widget.strings.badAddress);
      return;
    }
    setState(() {
      _error = null;
      _trying = true;
    });
    widget.onConnect(uri);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    return Panel(
      palette: p,
      title: s.appName,
      onClose: widget.onClose,
      closeLabel: s.close,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.serverAddress, style: textStyle(12, p.fgMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            autofocus: true,
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
