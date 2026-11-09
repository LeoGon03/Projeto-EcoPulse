import 'package:flutter/material.dart';
import '../models/relato_model.dart';

class NovoRelatoModal extends StatefulWidget {
  final Function(RelatoModel) onRelatoCriado;
  final double latitude;
  final double longitude;

  const NovoRelatoModal({
    Key? key,
    required this.onRelatoCriado,
    required this.latitude,
    required this.longitude,
  }) : super(key: key);

  @override
  State<NovoRelatoModal> createState() => _NovoRelatoModalState();
}

class _NovoRelatoModalState extends State<NovoRelatoModal> {
  final _formKey = GlobalKey<FormState>();
  final _descricaoController = TextEditingController();
  
  String _tipoRisco = 'ALAGAMENTO';
  double _grauSeveridade = 3.0;

  @override
  void dispose() {
    _descricaoController.dispose();
    super.dispose();
  }

  void _submeterFormulario() {
    if (_formKey.currentState!.validate()) {
      final novoRelato = RelatoModel(
        usuarioId: 'usr_mobile_local',
        descricao: _descricaoController.text.trim(),
        tipoRisco: _tipoRisco,
        grauSeveridade: _grauSeveridade.round(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        criadoEm: DateTime.now().toIso8601String(),
      );

      widget.onRelatoCriado(novoRelato);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Emitir Novo Alerta Ambiental',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Ponto selecionado: ${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<String>(
              value: _tipoRisco,
              decoration: const InputDecoration(
                labelText: 'Tipo de Risco',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warning_amber),
              ),
              items: const [
                DropdownMenuItem(value: 'ALAGAMENTO', child: Text('🌊 Alagamento')),
                DropdownMenuItem(value: 'QUALIDADE_AR', child: Text('🌬️ Qualidade do Ar')),
                DropdownMenuItem(value: 'ILHA_CALOR', child: Text('🔥 Ilha de Calor')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _tipoRisco = val);
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descricaoController,
              maxLines: 2,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição da Ocorrência',
                hintText: 'Ex: Acúmulo de água na via impede passagem de veículos',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Por favor, informe uma breve descrição.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text(
              'Grau de Severidade: ${_grauSeveridade.round()}/5',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Slider(
              value: _grauSeveridade,
              min: 1.0,
              max: 5.0,
              divisions: 4,
              label: _grauSeveridade.round().toString(),
              activeColor: Colors.redAccent,
              onChanged: (val) => setState(() => _grauSeveridade = val),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _submeterFormulario,
              icon: const Icon(Icons.send),
              label: const Text('PUBLICAR ALERTA', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}