import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';

enum TonyoPublicLink {
  privacy('https://jjjjhogan.github.io/tonyoapp/privacy/'),
  support('https://jjjjhogan.github.io/tonyoapp/');

  const TonyoPublicLink(this.url);

  final String url;
}

const _publicLinksChannel = MethodChannel('tonyo/public_links');

/// Public pages open only after a tap; account and wellness data are not sent.
Future<void> openTonyoPublicLink(
  BuildContext context,
  TonyoPublicLink link,
) async {
  var opened = false;
  try {
    opened =
        await _publicLinksChannel.invokeMethod<bool>('open', link.url) ?? false;
  } on PlatformException {
    // Keep the public address available if the system cannot open a browser.
  } on MissingPluginException {
    // Other platforms can still copy the address without an iOS handler.
  }
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.tr(
          'Could not open the website. Copy the link to your browser.',
        ),
      ),
      action: SnackBarAction(
        label: context.tr('Copy link'),
        onPressed: () => Clipboard.setData(ClipboardData(text: link.url)),
      ),
    ),
  );
}
