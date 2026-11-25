import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/network/api_error.dart';
import '../../core/plus_ledger.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t reach OneDay. Check your connection and try again.';

String _day(DateTime at) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}

/// OneDay Plus: what it adds, what is never sold, and subscribing or cancelling. Payment happens in Razorpay's
/// native checkout on Android and iOS; elsewhere the checkout link is shown to open in a browser.
class PlusScreen extends ConsumerStatefulWidget {
  const PlusScreen({super.key});

  @override
  ConsumerState<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends ConsumerState<PlusScreen> {
  PlusStatus? _status;
  String? _loadError;
  bool _busy = false;

  PlusLedgerRepository get _repo => ref.read(plusLedgerRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await _repo.plus();
      if (mounted) {
        setState(() {
          _status = status;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _subscribe() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final checkout = await _repo.subscribe();
      if (!mounted) return;
      final outcome = await ref.read(checkoutLauncherProvider).open(checkout);
      if (!mounted) return;
      switch (outcome.result) {
        case CheckoutResult.paid:
          _say('Paid. Plus turns on in a moment.');
          await _load();
          return;
        case CheckoutResult.cancelled:
          _say('Checkout closed. Nothing was charged.');
          return;
        case CheckoutResult.failed:
          _say(outcome.message ?? 'The payment didn\'t go through.');
          return;
        case CheckoutResult.unavailable:
          break; // no in-app checkout here: show the link
      }
      final url = checkout.url;
      if (url != null && url.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Finish on Razorpay'),
            content: SelectableText(
              'Open this link in your browser to pay with UPI Autopay:\n\n$url',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: url),
                  ).catchError((Object _) {});
                  Navigator.of(dialog).pop();
                },
                child: const Text('Copy link'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        _say('Checkout is ready. Finish the payment to turn on Plus.');
      }
      await _load();
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(PlusStatus status) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cancel Plus?'),
        content: Text(
          status.renewsOrEndsAt == null
              ? 'Plus stays on until the end of this period.'
              : 'Plus stays on until ${_day(status.renewsOrEndsAt!)}, then ends. You won\'t be charged again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep Plus'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Cancel Plus'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final next = await _repo.cancel();
      if (mounted) setState(() => _status = next);
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('OneDay Plus')),
      body: status == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x2,
                OdSpace.gutter,
                OdSpace.x6,
              ),
              children: [
                if (status.plus)
                  Text(
                    status.cancelAtPeriodEnd
                        ? 'Plus ends ${status.renewsOrEndsAt == null ? 'at the end of this period' : 'on ${_day(status.renewsOrEndsAt!)}'}.'
                        : 'You have Plus${status.renewsOrEndsAt == null ? '' : '. It renews on ${_day(status.renewsOrEndsAt!)}'}.',
                    style: context.type.titleLarge,
                  )
                else
                  Text(
                    status.price == null ? 'OneDay Plus' : 'Plus · ${status.price}',
                    style: context.type.titleLarge,
                  ),
                const SizedBox(height: OdSpace.x2),
                Text('What it adds', style: context.type.titleMedium),
                for (final b in status.benefits)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.add_circle_outline_rounded, color: context.od.brand),
                    title: Text(b),
                  ),
                const SizedBox(height: OdSpace.x2),
                Text('Never for sale', style: context.type.titleMedium),
                Text(
                  'Safety is the same for everyone. These are never part of Plus:',
                  style: context.type.bodyMedium,
                ),
                for (final n in status.neverSold)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.block_rounded, color: context.od.textTertiary),
                    title: Text(n),
                  ),
                const SizedBox(height: OdSpace.x3),
                if (!status.available && !status.plus)
                  Text(
                    'Plus isn\'t available yet.',
                    style: context.type.bodyLarge,
                  )
                else if (!status.plus)
                  OdButton(
                    label: 'Get Plus',
                    expand: true,
                    loading: _busy,
                    onPressed: _subscribe,
                  )
                else if (!status.cancelAtPeriodEnd)
                  OdButton(
                    label: 'Cancel Plus',
                    variant: OdButtonVariant.secondary,
                    expand: true,
                    loading: _busy,
                    onPressed: () => _cancel(status),
                  ),
              ],
            ),
    );
  }
}

/// The private Real Value Ledger: this month's real outcomes, and last week's recap.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  LedgerMonth? _month;
  WeeklyRecap? _week;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(plusLedgerRepositoryProvider);
    try {
      final month = await repo.ledger();
      WeeklyRecap? week;
      try {
        week = await repo.week();
      } catch (_) {
        week = null; // the recap is extra; the month still shows
      }
      if (!mounted) return;
      setState(() {
        _month = month;
        _week = week;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = _month;
    final week = _week;
    return Scaffold(
      appBar: AppBar(title: const Text('Your month')),
      body: month == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                OdSpace.gutter,
                OdSpace.x2,
                OdSpace.gutter,
                OdSpace.x6,
              ),
              children: [
                Text(
                  'Only you see this. It counts real moments, never time spent in the app.',
                  style: context.type.bodyMedium,
                ),
                const SizedBox(height: OdSpace.x2),
                if (week != null && week.ready) ...[
                  OdCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LAST WEEK',
                          style: context.type.labelSmall?.copyWith(
                            color: context.od.brand,
                            letterSpacing: 1,
                          ),
                        ),
                        if (week.highlight != null) ...[
                          const SizedBox(height: OdSpace.x1),
                          Text(week.highlight!, style: context.type.titleLarge),
                        ],
                        for (final line in week.lines)
                          Padding(
                            padding: const EdgeInsets.only(top: OdSpace.x0_5),
                            child: Text(line, style: context.type.bodyLarge),
                          ),
                        if (week.ending != null) ...[
                          const SizedBox(height: OdSpace.x1),
                          Text(week.ending!, style: context.type.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: OdSpace.x3),
                ],
                Text('This month', style: context.type.titleMedium),
                const SizedBox(height: OdSpace.x1),
                if (month.lines.isEmpty)
                  Text(
                    'Nothing yet this month. That\'s fine.',
                    style: context.type.bodyLarge,
                  ),
                for (final line in month.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OdSpace.x1),
                    child: Text(line, style: context.type.bodyLarge),
                  ),
              ],
            ),
    );
  }
}
