import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../data/models/delivery.dart';
import '../data/models/enums.dart';
import '../providers/core_providers.dart';
import 'common.dart';

/// Informations du colis : catégorie, description, photo, quantité, fragile, taille, poids.
class PackageForm extends ConsumerStatefulWidget {
  const PackageForm({super.key, required this.package, required this.onChanged, this.compact = false});
  final PackageInfo package;
  final VoidCallback onChanged;
  final bool compact;

  @override
  ConsumerState<PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends ConsumerState<PackageForm> {
  late final _desc = TextEditingController(text: widget.package.description);
  late final _weight = TextEditingController(text: widget.package.weightKg?.toString() ?? '');
  XFile? _photo;
  bool _uploading = false;

  PackageInfo get p => widget.package;

  Future<void> _pickPhoto(bool camera) async {
    final storage = ref.read(storageServiceProvider);
    final f = await storage.pickImage(camera: camera);
    if (f == null) return;
    setState(() {
      _photo = f;
      _uploading = true;
    });
    try {
      p.photoPath = await storage.uploadXFile('package-photos', f);
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
      setState(() => _photo = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Type de colis', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      GridView(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisExtent: 104,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final c in PackageCategory.values)
            ChoiceTile(
              label: c.label,
              icon: c.icon,
              selected: p.category == c,
              onTap: () {
                setState(() {
                  p.category = c;
                  if (c == PackageCategory.gros_colis && p.size.index < PackageSize.grand.index) p.size = PackageSize.grand;
                  if (c == PackageCategory.colis_moyen && p.size == PackageSize.petit) p.size = PackageSize.moyen;
                });
                widget.onChanged();
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _desc,
        decoration: const InputDecoration(labelText: 'Description (ex. 2 paires de chaussures)', prefixIcon: Icon(Icons.notes)),
        maxLines: 2,
        minLines: 1,
        onChanged: (v) {
          p.description = v;
          widget.onChanged();
        },
      ),
      const SizedBox(height: 16),
      const Text('Taille approximative', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in PackageSize.values)
          ChoiceChip(
            label: Text('${s.label} · ${s.hint}'),
            selected: p.size == s,
            onSelected: (_) {
              setState(() => p.size = s);
              widget.onChanged();
            },
          ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Quantité', style: TextStyle(fontWeight: FontWeight.w700))),
        IconButton.filledTonal(
          onPressed: p.quantity > 1
              ? () {
                  setState(() => p.quantity--);
                  widget.onChanged();
                }
              : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(width: 44, child: Text('${p.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(
          onPressed: () {
            setState(() => p.quantity++);
            widget.onChanged();
          },
          icon: const Icon(Icons.add),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: p.fragile,
        onChanged: (v) {
          setState(() => p.fragile = v);
          widget.onChanged();
        },
        title: const Text('Fragile', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Le livreur sera prévenu de manipuler avec soin'),
        secondary: const Icon(Icons.warning_amber_rounded, color: AppColors.accent),
      ),
      if (!widget.compact) ...[
        TextFormField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Poids approximatif en kg (facultatif)', prefixIcon: Icon(Icons.scale_outlined)),
          onChanged: (v) {
            p.weightKg = double.tryParse(v.replaceAll(',', '.'));
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        Row(children: [
          if (_photo != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder(
                  future: _photo!.readAsBytes(),
                  builder: (_, s) => s.hasData
                      ? Image.memory(s.data!, width: 64, height: 64, fit: BoxFit.cover)
                      : const SizedBox(width: 64, height: 64),
                ),
              ),
            ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : () => _pickPhoto(true),
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_camera_outlined),
              label: Text(p.photoPath == null ? 'Photo (facultatif)' : 'Changer la photo'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: _uploading ? null : () => _pickPhoto(false),
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Galerie',
          ),
        ]),
      ],
    ]);
  }
}
