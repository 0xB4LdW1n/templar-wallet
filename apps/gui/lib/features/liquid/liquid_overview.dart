// The top of the Liquid page: Liquid's own balance and its chart (the
// Dashboard's chart, smaller, drawn in Liquid's hue), and beside it the split
// of the Liquid assets (design.md, "The moments").
//
// Two inputs, neither required to render: the wallet's balance history (its
// `lbtc_sats` step function) and the BTC price series. The chart is L-BTC
// valued in fiat while a price exists, and the coin balance otherwise.
//
// The split is measured in what the engine and the price feed can actually
// value. L-BTC is valued through the BTC price (it is pegged one to one, the
// same rule the asset rows already follow). No issued token has a price —
// the engine reports `fiat_estimate: null` for every asset and the price
// service knows only BTC — so tokens have no slice: the ring says how many
// were left out, and the assets list under it names them. Nothing here
// guesses a value.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../features/dashboard/models/balance_history.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/price_history_service.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/privacy.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/share_donut.dart';
import '../../shared/widgets/value_chart.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

enum _Range {
  d7('7D', 'in 7 days', Duration(days: 7), 7),
  d30('30D', 'in 30 days', Duration(days: 30), 30),
  d90('90D', 'in 90 days', Duration(days: 90), 90),
  y1('1Y', 'in 1 year', Duration(days: 365), 365),
  all('All', 'all time', null, 365);

  const _Range(this.label, this.period, this.window, this.priceDays);
  final String label;
  final String period;
  final Duration? window;
  final int priceDays;
}

/// One Liquid asset as the split sees it.
class LiquidShare {
  const LiquidShare({
    required this.asset,
    required this.name,
    required this.amount,
  });

  final AssetBalance asset;
  final String name;

  /// Formatted amount, in the asset's own unit.
  final String amount;

  bool get isLbtc => asset.ticker == 'LBTC';
}

/// The Liquid page's hero: balance and chart on the left, the split on the
/// right (stacked on a phone).
class LiquidOverview extends StatefulWidget {
  const LiquidOverview({
    super.key,
    required this.lbtcSats,
    required this.shares,
    required this.history,
    required this.historyFailed,
  });

  /// The L-BTC balance the engine reports (the figure).
  final int lbtcSats;

  /// Every visible Liquid asset, L-BTC first, in the engine's order.
  final List<LiquidShare> shares;

  final BalanceHistory? history;
  final bool historyFailed;

  @override
  State<LiquidOverview> createState() => _LiquidOverviewState();
}

class _LiquidOverviewState extends State<LiquidOverview> {
  _Range _range = _Range.d30;

  List<PricePoint> _prices = const [];
  bool _pricesLoaded = false;
  bool _fetching = false;
  String _pricesKey = '';

  List<ChartPoint>? _series;
  String _seriesKey = '';

  @override
  void initState() {
    super.initState();
    _loadPrices();
    PriceService.instance.addListener(_loadPrices);
  }

  @override
  void dispose() {
    PriceService.instance.removeListener(_loadPrices);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiquidOverview old) {
    super.didUpdateWidget(old);
    if (old.history != widget.history) _loadPrices();
  }

  int get _priceDays {
    if (_range.window != null) return _range.priceDays;
    final points = widget.history?.points ?? const <BalanceHistoryPoint>[];
    if (points.isEmpty) return 30;
    final span = DateTime.now().difference(points.first.time).inDays;
    for (final d in const [7, 30, 90, 365]) {
      if (span <= d) return d;
    }
    return PriceHistoryService.allDays;
  }

  Future<void> _loadPrices() async {
    final currency = PriceService.instance.currency;
    final days = _priceDays;
    final key = '$currency|$days';
    final retryable = _pricesLoaded && _prices.isEmpty;
    if (_fetching || (key == _pricesKey && !retryable)) return;
    _fetching = true;
    _pricesKey = key;
    final series = await PriceHistoryService.instance.series(
      currency: currency,
      days: days,
    );
    _fetching = false;
    if (!mounted) return;
    setState(() {
      _prices = series;
      _pricesLoaded = true;
    });
  }

  void _select(_Range r) {
    if (r == _range) return;
    setState(() => _range = r);
    _loadPrices();
  }

  /// "Now", quantised to the hour so the memo key holds between rebuilds.
  DateTime _now() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    const hour = 3600 * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms ~/ hour * hour + hour);
  }

  /// The L-BTC step function clipped to the window, always two samples.
  List<(DateTime, int)> _samples(BalanceHistory h, DateTime now) {
    final points = h.points;
    final start = _range.window != null
        ? now.subtract(_range.window!)
        : (points.isNotEmpty
              ? points.first.time
              : now.subtract(const Duration(days: 30)));
    final out = <(DateTime, int)>[];
    int? carried;
    for (final p in points) {
      if (p.time.isBefore(start)) {
        carried = p.lbtcSats;
        continue;
      }
      if (p.time.isAfter(now)) continue;
      out.add((p.time, p.lbtcSats));
    }
    if (carried != null) out.insert(0, (start, carried));
    if (out.isEmpty) out.add((start, h.lbtcSats));
    out.add((now, h.lbtcSats));
    return out;
  }

  List<ChartPoint> _points(bool fiat) {
    final h = widget.history;
    final hKey = h == null
        ? 'none'
        : '${h.points.length}.${h.lbtcSats}.'
              '${h.points.isEmpty ? 0 : h.points.last.time.millisecondsSinceEpoch}';
    final pKey = _prices.isEmpty
        ? '0'
        : '${_prices.length}.${_prices.last.price}';
    final now = _now();
    final key =
        '$hKey|${_range.name}|$fiat|$pKey|${now.millisecondsSinceEpoch}';
    if (_series != null && key == _seriesKey) return _series!;

    final List<ChartPoint> built;
    if (h == null) {
      built = const [];
    } else {
      final samples = _samples(h, now);
      if (!fiat) {
        built = [for (final (t, v) in samples) ChartPoint(t, v.toDouble())];
      } else {
        // Resample the step function onto an even grid, so the line moves
        // with the price between transactions.
        final price = PriceHistoryService.instance;
        final start = samples.first.$1;
        final span = now.difference(start).inMilliseconds;
        const buckets = 90;
        final out = <ChartPoint>[];
        var index = 0;
        var held = samples.first.$2;
        for (var i = 0; i <= buckets; i++) {
          final t = span <= 0
              ? now
              : start.add(Duration(milliseconds: span * i ~/ buckets));
          while (index < samples.length && !samples[index].$1.isAfter(t)) {
            held = samples[index].$2;
            index++;
          }
          out.add(ChartPoint(t, held / 1e8 * price.priceAt(t, _prices)));
          if (span <= 0) break;
        }
        built = out;
      }
    }
    _series = built;
    _seriesKey = key;
    return built;
  }

  double? _delta(List<ChartPoint> p) {
    if (p.length < 2) return null;
    final first = p.first.value;
    if (first <= 0) return null;
    return (p.last.value - first) / first * 100;
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    context.select<AppState, String>((st) => st.fiatCurrency);
    final masked = balancesHidden(context);

    return AnimatedBuilder(
      animation: PriceService.instance,
      builder: (context, _) {
        final price = PriceService.instance;
        final hasAnyPrice = _prices.isNotEmpty || price.btcPrice > 0;
        final fiat = !(_pricesLoaded && _prices.isEmpty) && hasAnyPrice;
        final points = _points(fiat);

        final balance = _Balance(
          sats: widget.lbtcSats,
          useSats: useSats,
          masked: masked,
          delta: masked ? null : _delta(points),
          period: _range.period,
        );
        final rangeSwitch = SegmentedSwitch<_Range>(
          dense: true,
          expand: phone,
          selected: _range,
          onChanged: _select,
          options: [
            for (final r in _Range.values) SegOption(value: r, label: r.label),
          ],
        );
        final symbol = price.symbol;
        final chart = ValueChart(
          height: phone ? 140 : 260,
          points: points,
          // Liquid's own hue, not the accent: this is the chain's page, and
          // the line is the chain's balance.
          lineColor: AppScheme.of(context).liquid,
          axes: true,
          markLatest: true,
          formatValue: (v) => masked
              ? kMaskedAmount
              : fiat
              ? PriceService.formatFiat(v, symbol)
              : PriceService.formatUnit(v.round(), sat: useSats, coin: 'LBTC'),
          formatAxis: (v, step) => masked
              ? ''
              : fiat
              ? liquidAxisLabel(v, step, prefix: symbol)
              : useSats
              ? liquidAxisLabel(v, step)
              : liquidAxisLabel(v / 1e8, step / 1e8),
          emptyMessage: widget.history != null
              ? 'No history yet'
              : widget.historyFailed
              ? 'Balance history unavailable'
              : 'Loading history…',
          animationKey: '${_range.name}|$fiat',
        );

        final split = _Split(
          shares: widget.shares,
          masked: masked,
          useSats: useSats,
          phone: phone,
        );

        if (phone) {
          return HeroPanel(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                balance,
                const SizedBox(height: AppSpacing.lg),
                chart,
                const SizedBox(height: AppSpacing.md),
                rangeSwitch,
                const SizedBox(height: AppSpacing.lg),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppScheme.of(context).edge,
                ),
                const SizedBox(height: AppSpacing.lg),
                split,
              ],
            ),
          );
        }
        final s = AppScheme.of(context);
        return HeroPanel(
          // Intrinsic height: the hairline between the two halves runs the
          // panel's whole height, and the ring centres against the chart.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: balance),
                          const SizedBox(width: AppSpacing.lg),
                          rangeSwitch,
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      chart,
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.only(left: AppSpacing.xl),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: s.edge)),
                    ),
                    child: split,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Liquid balance", the L-BTC figure with its quiet unit, then its fiat
/// value and the change over the chart's range.
class _Balance extends StatelessWidget {
  const _Balance({
    required this.sats,
    required this.useSats,
    required this.masked,
    required this.delta,
    required this.period,
  });

  final int sats;
  final bool useSats;
  final bool masked;
  final double? delta;
  final String period;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final coin = PriceService.formatUnit(sats, sat: useSats, coin: 'LBTC');
    final i = coin.lastIndexOf(' ');
    final figure = coin.substring(0, i);
    final unit = coin.substring(i + 1);
    final fiat = PriceService.instance.fiatDisplay(sats);
    final d = delta;
    final quiet = <InlineSpan>[
      if (fiat != null && !masked)
        TextSpan(
          text: fiat,
          style: AppTypography.numericSmall.copyWith(color: s.inkSecondary),
        ),
      if (d != null) ...[
        if (fiat != null && !masked)
          TextSpan(
            text: '  ·  ',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        TextSpan(
          text: '${d >= 0 ? '+' : '−'}${d.abs().toStringAsFixed(1)}% ',
          style: AppTypography.numericSmall.copyWith(color: s.inkSecondary),
        ),
        TextSpan(
          text: period,
          style: AppTypography.caption.copyWith(color: s.inkFaint),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Liquid balance',
          style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                masked ? kMaskedAmount : figure,
                style: AppTypography.balanceLargeOf(
                  context,
                ).copyWith(color: s.ink),
              ),
              if (!masked) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  unit,
                  style: AppTypography.numericLargeOf(
                    context,
                  ).copyWith(color: s.inkFaint),
                ),
              ],
            ],
          ),
        ),
        if (quiet.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text.rich(TextSpan(children: quiet), maxLines: 1),
        ],
      ],
    );
  }
}

/// The split: an eyebrow, the ring, and a legend of one line per part.
/// What the shares are measured in is the eyebrow's tooltip, not a paragraph.
class _Split extends StatelessWidget {
  const _Split({
    required this.shares,
    required this.masked,
    required this.useSats,
    required this.phone,
  });

  final List<LiquidShare> shares;
  final bool masked;
  final bool useSats;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final price = PriceService.instance;
    // Only L-BTC has a value (sats, i.e. the BTC price). A token has no
    // price from the engine or the feed, so it has no slice: it is counted
    // in the note under the legend and named in the assets list.
    final slices = <ShareSlice>[];
    var valuedSats = 0;
    var unpriced = 0;
    for (final a in shares) {
      if (!a.isLbtc) {
        unpriced++;
        continue;
      }
      if (a.asset.amount <= 0) continue;
      valuedSats += a.asset.amount;
      slices.add(
        ShareSlice(
          id: a.asset.assetId,
          label: a.name,
          amount: masked ? kMaskedAmount : a.amount,
          // The chain's own coin keeps the chain hue.
          color: s.liquid,
          value: a.asset.amount.toDouble(),
        ),
      );
    }
    final fiat = price.fiatDisplay(valuedSats);
    final total = masked
        ? kMaskedAmount
        : fiat ??
              PriceService.formatUnit(valuedSats, sat: useSats, coin: 'BTC');
    final measure = fiat != null
        ? 'Shares by value in ${price.currency}, at the BTC price'
        : 'Shares by value in BTC';

    final Widget ring = shares.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              'No Liquid assets yet',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
          )
        : ShareDonut(
            slices: slices,
            totalLabel: 'Valued',
            totalValue: total,
            footnote: unpriced == 0
                ? null
                : unpriced == 1
                ? '1 asset without a price'
                : '$unpriced assets without a price',
            legendBeside: false,
            size: phone ? 168 : 176,
            masked: masked,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Beside the chart the block takes the panel's height and the ring
      // sits in the middle of it; stacked on a phone it is as tall as it is.
      mainAxisSize: phone ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: measure,
            child: Text(
              'Split',
              style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (phone) ring else Expanded(child: Center(child: ring)),
      ],
    );
  }
}

/// A y-axis tick at the chart's edge — the only place a figure may be
/// shortened (`€1.2k`): a tick names a gridline, it is not a balance.
/// [step] is the gap between ticks, so the label carries exactly the
/// decimals that tell two ticks apart.
String liquidAxisLabel(double v, double step, {String prefix = ''}) {
  int decimalsFor(double st) {
    var d = 0;
    var x = st.abs();
    while (d < 8 && (x - x.roundToDouble()).abs() > 1e-6 * math.max(1, x)) {
      x *= 10;
      d++;
    }
    return d;
  }

  String trim(String s) =>
      s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

  String grouped(int n) {
    final digits = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  final a = v.abs();
  if (a >= 1e6 && step >= 1e4) {
    return '$prefix${trim((v / 1e6).toStringAsFixed(decimalsFor(step / 1e6)))}M';
  }
  if (a >= 1e4 && step >= 100) {
    return '$prefix${trim((v / 1e3).toStringAsFixed(decimalsFor(step / 1e3)))}k';
  }
  final d = decimalsFor(step);
  if (d == 0) return '$prefix${grouped(v.round())}';
  final fixed = v.toStringAsFixed(d);
  final dot = fixed.indexOf('.');
  return '$prefix${grouped(int.parse(fixed.substring(0, dot)))}'
      '${fixed.substring(dot)}';
}
