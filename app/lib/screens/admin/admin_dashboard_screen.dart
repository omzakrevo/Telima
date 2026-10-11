import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/enums.dart';
import '../../data/models/json.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import 'admin_payments_screen.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/motion.dart';

class _Period {
  const _Period(this.label, this.days);
  final String label;
  final int days;
}

const _periods = [_Period('Aujourd\'hui', 1), _Period('7 jours', 7), _Period('30 jours', 30)];

final _periodProvider = NotifierProvider<_PeriodNotifier, int>(_PeriodNotifier.new);

class _PeriodNotifier extends Notifier<int> {
  @override
  int build() => 1;
  void set(int days) => state = days;
}

final _statsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final days = ref.watch(_periodProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  // rafraîchissement automatique toutes les 30 secondes
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(adminRepositoryProvider).dashboard(from, now.add(const Duration(minutes: 1)));
});

final _dailyProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(adminRepositoryProvider).dailyStats(14));

/// Connexions par jour (utilisateurs connectés, comptés une fois par jour).
final _activityProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(adminRepositoryProvider).activity(30));

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(_periodProvider);
    final stats = ref.watch(_statsProvider);
    final daily = ref.watch(_dailyProvider);
    final activity = ref.watch(_activityProvider);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 1300 ? 6 : (width > 900 ? 4 : 2);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_statsProvider);
        ref.invalidate(_dailyProvider);
        ref.invalidate(_activityProvider);
      },
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in _periods)
            ChoiceChip(label: Text(p.label), selected: period == p.days, onSelected: (_) => ref.read(_periodProvider.notifier).set(p.days)),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () {
              ref.invalidate(_statsProvider);
              ref.invalidate(_dailyProvider);
              ref.invalidate(_activityProvider);
              ref.invalidate(adminPendingCountsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 12),
        const _ToDoBanner(),
        const SizedBox(height: 4),
        AsyncBody<Map<String, dynamic>>(
          value: stats,
          onRetry: () => ref.invalidate(_statsProvider),
          builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Bloc principal : chiffre d'affaires sur fond encre
            FadeSlideIn(child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(28)),
              child: Wrap(spacing: 40, runSpacing: 20, crossAxisAlignment: WrapCrossAlignment.end, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Chiffre d’affaires', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  const SizedBox(height: 6),
                  CountUpFcfa(value: (s['revenue'] as num?) ?? 0,
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
                ]),
                _HeroFigure(label: 'Commissions', value: fcfa(s['commissions'] as num?)),
                _HeroFigure(label: 'Paiements encaissés', value: fcfa(s['payments'] as num?)),
                _HeroFigure(label: 'Retraits payés', value: fcfa(s['withdrawals_paid'] as num?)),
              ]),
            )),
            const SectionTitle('Activité'),
            GridView.count(
              crossAxisCount: cols > 4 ? 4 : cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols >= 4 ? 1.65 : 1.4,
              children: [
                FadeSlideIn.staggered(index: 1, child: StatCard(label: 'Commandes sur la période', value: '${s['orders']}', icon: Icons.receipt_long_rounded, image: Ico3D.package, color: AppColors.ink, onTap: () => context.go('/admin/orders'))),
                FadeSlideIn.staggered(index: 2, child: StatCard(label: 'En attente de livreur', value: '${s['orders_searching']}', icon: Icons.hourglass_top_rounded, image: Ico3D.hourglass, color: AppColors.accent, onTap: () => context.go('/admin/orders'))),
                FadeSlideIn.staggered(index: 3, child: StatCard(label: 'En cours', value: '${s['orders_active']}', icon: Icons.near_me_rounded, image: Ico3D.scooter, color: AppColors.ink, onTap: () => context.go('/admin/map'))),
                FadeSlideIn.staggered(index: 4, child: StatCard(label: 'Terminées · ${s['cancelled']} annulée(s)', value: '${s['completed']}', icon: Icons.check_rounded, image: Ico3D.check, color: AppColors.primary)),
              ],
            ),
            const SectionTitle('Équipe et retraits'),
            GridView.count(
              crossAxisCount: cols > 3 ? 3 : cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: cols > 2 ? 2.15 : 1.4,
              children: [
                FadeSlideIn.staggered(index: 5, child: StatCard(label: 'Clients', value: '${s['clients']}', icon: Icons.people_alt_rounded, image: Ico3D.people, color: AppColors.ink, onTap: () => context.go('/admin/users'))),
                FadeSlideIn.staggered(index: 6, child: StatCard(
                  label: 'Livreurs · ${s['drivers_online']} en ligne',
                  value: '${s['drivers']}',
                  icon: Icons.delivery_dining_rounded,
                  image: Ico3D.truck,
                  color: AppColors.ink,
                  onTap: () => context.go('/admin/drivers'),
                )),
                FadeSlideIn.staggered(index: 7, child: StatCard(
                  label: 'Retraits en attente (${s['withdrawals_pending_count']})',
                  value: fcfa(s['withdrawals_pending'] as num?),
                  icon: Icons.schedule_rounded,
                  image: Ico3D.moneyBag,
                  color: asInt(s['withdrawals_pending_count']) > 0 ? AppColors.danger : AppColors.ink,
                  onTap: () => context.go('/admin/finance'),
                )),
              ],
            ),
            if (asInt(s['drivers_pending']) > 0 || asInt(s['support_open']) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (asInt(s['drivers_pending']) > 0)
                    ActionChip(
                      avatar: const Icon(Icons.badge, color: AppColors.accent),
                      label: Text('${s['drivers_pending']} inscription(s) livreur à valider'),
                      onPressed: () => context.go('/admin/drivers'),
                    ),
                  if (asInt(s['support_open']) > 0)
                    ActionChip(
                      avatar: const Icon(Icons.support_agent, color: AppColors.info),
                      label: Text('${s['support_open']} demande(s) de support'),
                      onPressed: () => context.go('/admin/support'),
                    ),
                ]),
              ),
            if ((s['payments_by_method'] as Map?)?.isNotEmpty ?? false) ...[
              const SectionTitle('Paiements par moyen'),
              Card(
                child: Column(children: [
                  for (final e in (s['payments_by_method'] as Map).entries)
                    ListTile(
                      leading: Icon(PaymentMethod.parse(e.key as String).icon),
                      title: Text(PaymentMethod.parse(e.key as String).label),
                      trailing: Text(fcfa(e.value as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            ],
          ]),
        ),
        const SectionTitle('Connexions'),
        AsyncBody<Map<String, dynamic>>(
          value: activity,
          onRetry: () => ref.invalidate(_activityProvider),
          builder: (a) {
            final days = (a['days'] as List).cast<Map<String, dynamic>>();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GridView.count(
                crossAxisCount: cols > 4 ? 4 : cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols >= 4 ? 1.9 : 1.4,
                children: [
                  FadeSlideIn.staggered(index: 1, child: StatCard(label: 'Connectés aujourd’hui', value: '${a['active_today']}', icon: Icons.people_alt_rounded, image: Ico3D.people, color: AppColors.primary)),
                  FadeSlideIn.staggered(index: 2, child: StatCard(label: 'Connectés sur 7 jours', value: '${a['active_7d']}', icon: Icons.groups_rounded, image: Ico3D.people, color: AppColors.ink)),
                  FadeSlideIn.staggered(index: 3, child: StatCard(label: 'Connectés sur 30 jours', value: '${a['active_30d']}', icon: Icons.groups_rounded, image: Ico3D.people, color: AppColors.ink)),
                  FadeSlideIn.staggered(index: 4, child: StatCard(label: 'Comptes inscrits', value: '${a['total_users']}', icon: Icons.groups_rounded, image: Ico3D.people, color: AppColors.ink, onTap: () => context.go('/admin/users'))),
                ],
              ),
              const SizedBox(height: 12),
              _ChartCard(title: 'Personnes connectées par jour (30 jours)', child: _ActivityChart(rows: days)),
            ]);
          },
        ),
        const SectionTitle('Activité des 14 derniers jours'),
        AsyncBody<List<Map<String, dynamic>>>(
          value: daily,
          onRetry: () => ref.invalidate(_dailyProvider),
          builder: (rows) => Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(
              width: width > 1100 ? (width - 340) / 2 : double.infinity,
              child: _ChartCard(title: 'Commandes / jour', child: _OrdersChart(rows: rows)),
            ),
            SizedBox(
              width: width > 1100 ? (width - 340) / 2 : double.infinity,
              child: _ChartCard(title: 'Chiffre d\'affaires / jour (FCFA)', child: _RevenueChart(rows: rows)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: child),
          ]),
        ),
      );
}

String _dayLabel(dynamic d) {
  final dt = DateTime.tryParse(d.toString());
  return dt == null ? '' : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => BarChart(BarChartData(
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final r = rows[group.x];
              return BarTooltipItem('${_dayLabel(r['day'])}\n${r['active']} connecté(s)', const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12));
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= rows.length || i % 5 != 0) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(_dayLabel(rows[i]['day']), style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: asInt(rows[i]['active']).toDouble(), color: i == rows.length - 1 ? AppColors.accent : AppColors.primary, width: 7),
            ]),
        ],
      ));
}

class _OrdersChart extends StatelessWidget {
  const _OrdersChart({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => BarChart(BarChartData(
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= rows.length || (rows.length > 7 && i.isOdd)) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(_dayLabel(rows[i]['day']), style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: asInt(rows[i]['completed']).toDouble(), color: AppColors.primary, width: 7),
              BarChartRodData(toY: asInt(rows[i]['cancelled']).toDouble(), color: AppColors.danger, width: 7),
              BarChartRodData(toY: asInt(rows[i]['orders']).toDouble(), color: AppColors.info.withValues(alpha: 0.4), width: 7),
            ]),
        ],
      ));
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => LineChart(LineChartData(
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= rows.length || (rows.length > 7 && i.isOdd)) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(_dayLabel(rows[i]['day']), style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            preventCurveOverShooting: true,
            color: const Color(0xFF7C3AED),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF7C3AED).withValues(alpha: 0.1)),
            spots: [for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), asInt(rows[i]['revenue']).toDouble())],
          ),
          LineChartBarData(
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            spots: [for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), asInt(rows[i]['commissions']).toDouble())],
          ),
        ],
      ));
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      ]);
}

/// À traiter : paiements Mobile Money déclarés et retraits en attente.
class _ToDoBanner extends ConsumerWidget {
  const _ToDoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(adminPendingCountsProvider).value;
    if (c == null) return const SizedBox.shrink();
    final pay = (c['payments_to_verify'] as num?)?.toInt() ?? 0;
    final wd = (c['withdrawals_pending'] as num?)?.toInt() ?? 0;
    if (pay == 0 && wd == 0) return const SizedBox.shrink();
    Widget tile(String text, int n, String route, IconData icon) => Expanded(
          child: Material(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.go(route),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(icon, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (pay > 0) tile('Paiements à vérifier', pay, '/admin/payments', Icons.fact_check_rounded),
        if (pay > 0 && wd > 0) const SizedBox(width: 10),
        if (wd > 0) tile('Retraits à verser', wd, '/admin/finance', Icons.outbox_rounded),
      ]),
    );
  }
}
