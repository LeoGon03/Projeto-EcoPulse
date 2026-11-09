class RelatoModel {
  final int? id;
  final String usuarioId;
  final String descricao;
  final String tipoRisco;
  final int grauSeveridade;
  final double latitude;
  final double longitude;
  final String? criadoEm;
  final bool isSynced;

  RelatoModel({
    this.id,
    required this.usuarioId,
    required this.descricao,
    required this.tipoRisco,
    required this.grauSeveridade,
    required this.latitude,
    required this.longitude,
    this.criadoEm,
    this.isSynced = true,
  });

  factory RelatoModel.fromJson(Map<String, dynamic> json) {
    String tipo = json['tipo_risco'] ?? '';
    // Padroniza relatos antigos gravados como 'AQI' para 'QUALIDADE_AR'
    if (tipo.toUpperCase() == 'AQI') {
      tipo = 'QUALIDADE_AR';
    }

    return RelatoModel(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      usuarioId: json['usuario_id'] ?? '',
      descricao: json['descricao'] ?? '',
      tipoRisco: tipo,
      grauSeveridade: json['grau_severidade'] ?? 1,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      criadoEm: json['criado_em'],
      isSynced: json['is_synced'] == 1 ||
          json['is_synced'] == true ||
          (json['is_synced'] == null && json['id'] != null),
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'usuario_id': usuarioId,
      'descricao': descricao,
      'tipo_risco': tipoRisco,
      'grau_severidade': grauSeveridade,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  Map<String, dynamic> toSqliteJson() {
    final Map<String, dynamic> data = {
      'usuario_id': usuarioId,
      'descricao': descricao,
      'tipo_risco': tipoRisco,
      'grau_severidade': grauSeveridade,
      'latitude': latitude,
      'longitude': longitude,
      'is_synced': isSynced ? 1 : 0,
    };
    if (id != null) data['id'] = id;
    if (criadoEm != null) data['criado_em'] = criadoEm;
    return data;
  }

  RelatoModel copyWith({bool? isSynced, int? id}) {
    return RelatoModel(
      id: id ?? this.id,
      usuarioId: usuarioId,
      descricao: descricao,
      tipoRisco: tipoRisco,
      grauSeveridade: grauSeveridade,
      latitude: latitude,
      longitude: longitude,
      criadoEm: criadoEm,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}