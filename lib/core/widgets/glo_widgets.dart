import 'package:flutter/material.dart';
import '../theme/glo_theme.dart';

class GloLogo extends StatelessWidget {
  final double size;
  const GloLogo({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Image.asset('assets/branding/glo_logo.png', width: size, height: size, fit: BoxFit.contain);
}

class StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const StatusChip({super.key, required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))]),
      );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle({super.key, required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: GloColors.ink)), if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700)))]);
}

class AssuranceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool verified;
  const AssuranceTile({super.key, required this.icon, required this.title, required this.subtitle, this.verified = true});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: GloColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: GloColors.lightGreen, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: GloColors.darkGreen, size: 21)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 11.5, color: GloColors.muted))])),
          Icon(verified ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: verified ? GloColors.primary : GloColors.amber, size: 21),
        ]),
      );
}

class GloNavItem {
  final IconData icon, selectedIcon;
  final String label;
  const GloNavItem(this.icon, this.selectedIcon, this.label);
}

class GloBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<GloNavItem> items;
  const GloBottomNav({super.key, required this.index, required this.onChanged, required this.items});

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onChanged,
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: GloColors.lightGreen,
        destinations: [
          for (final i in items)
            NavigationDestination(icon: Icon(i.icon), selectedIcon: Icon(i.selectedIcon), label: i.label),
        ],
      );
}
