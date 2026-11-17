import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/scan_button.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The way into a `templar://` request when the link did not arrive by itself.
///
/// Normally the site opens Templar: the browser hands the link to the OS and
/// the request screen comes up. This is the fallback for when it does not —
/// the scheme is not registered yet, the link was read on another device, or
/// it came as a QR on the loan page. Lives in one widget because both the
/// request screen and Settings › Templar Protocol offer it, and a second copy
/// would be a second set of words for the same box.
///
/// A mono field (the link is compared character by character), paste and —
/// where there is a camera — scan at its edge, and one neutral action: the
/// pages that host it keep their own primary.
class ProtocolPasteCard extends StatefulWidget {
  const ProtocolPasteCard({
    super.key,
    required this.onOpen,
    this.title = 'Open a templar:// link',
    this.subtitle,
  });

  /// Called with the trimmed link when the user asks to open it.
  final void Function(String link) onOpen;

  final String title;
  final String? subtitle;

  @override
  State<ProtocolPasteCard> createState() => _ProtocolPasteCardState();
}

class _ProtocolPasteCardState extends State<ProtocolPasteCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) widget.onOpen(text);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _controller.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return FormCard(
      title: widget.title,
      subtitle:
          widget.subtitle ??
          'Paste a link from a Templar Protocol site, or scan its QR. Clicking such a '
              'link in your browser opens this screen directly once Templar is '
              'registered as its handler.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('protocol-paste-field'),
            controller: _controller,
            minLines: phone ? 3 : 2,
            maxLines: 3,
            style: AppTypography.mono.copyWith(color: s.ink),
            decoration: InputDecoration(
              hintText: 'templar://connect?url=https://…&nonce=…',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('protocol-paste-clipboard'),
                    tooltip: 'Paste',
                    onPressed: _paste,
                    icon: Icon(
                      Icons.content_paste_outlined,
                      size: phone ? 20 : AppSpacing.icon,
                      color: s.inkSecondary,
                    ),
                  ),
                  // Renders nothing where there is no camera, so the box
                  // keeps its full width on a desktop without one.
                  ScanIconButton(
                    controller: _controller,
                    title: 'Scan a templar:// link',
                    tooltip: 'Scan the link',
                    onScanned: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _open(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              key: const Key('protocol-paste-open'),
              label: 'Open',
              onPressed: _open,
              isFullWidth: phone,
            ),
          ),
        ],
      ),
    );
  }
}
