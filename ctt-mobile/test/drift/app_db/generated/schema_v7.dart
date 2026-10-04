// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class SyncPendientes extends Table
    with TableInfo<SyncPendientes, SyncPendientesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncPendientes(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> secuencia = GeneratedColumn<int>(
      'secuencia', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
      'idempotency_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
      'empresa_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> usuarioId = GeneratedColumn<String>(
      'usuario_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> instalacionId = GeneratedColumn<String>(
      'instalacion_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> tipoEntidad = GeneratedColumn<String>(
      'tipo_entidad', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> entidadId = GeneratedColumn<String>(
      'entidad_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> accion = GeneratedColumn<String>(
      'accion', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
      'payload_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<int> versionBase = GeneratedColumn<int>(
      'version_base', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> creadoEnDispositivo =
      GeneratedColumn<DateTime>('creado_en_dispositivo', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
      'estado', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'pendiente\''));
  late final GeneratedColumn<String> motivo = GeneratedColumn<String>(
      'motivo', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> conflictoId = GeneratedColumn<String>(
      'conflicto_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> acknowledged = GeneratedColumn<bool>(
      'acknowledged', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("acknowledged" IN (0, 1))'),
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<int> intentosRed = GeneratedColumn<int>(
      'intentos_red', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<int> intentosServidor = GeneratedColumn<int>(
      'intentos_servidor', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<DateTime> proximoIntentoEn =
      GeneratedColumn<DateTime>('proximo_intento_en', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> ultimoIntentoEn =
      GeneratedColumn<DateTime>('ultimo_intento_en', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<int> ultimoErrorCodigo = GeneratedColumn<int>(
      'ultimo_error_codigo', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<String> ultimoError = GeneratedColumn<String>(
      'ultimo_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> tomadoPor = GeneratedColumn<String>(
      'tomado_por', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> tomadoHasta = GeneratedColumn<DateTime>(
      'tomado_hasta', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<DateTime> sincronizadoEn =
      GeneratedColumn<DateTime>('sincronizado_en', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<int> versionResultante = GeneratedColumn<int>(
      'version_resultante', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<String> rechazoId = GeneratedColumn<String>(
      'rechazo_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        secuencia,
        id,
        idempotencyKey,
        empresaId,
        usuarioId,
        instalacionId,
        tipoEntidad,
        entidadId,
        accion,
        payload,
        payloadVersion,
        versionBase,
        creadoEnDispositivo,
        estado,
        motivo,
        conflictoId,
        acknowledged,
        intentosRed,
        intentosServidor,
        proximoIntentoEn,
        ultimoIntentoEn,
        ultimoErrorCodigo,
        ultimoError,
        tomadoPor,
        tomadoHasta,
        sincronizadoEn,
        versionResultante,
        rechazoId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pendientes';
  @override
  Set<GeneratedColumn> get $primaryKey => {secuencia};
  @override
  SyncPendientesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPendientesData(
      secuencia: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}secuencia'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      idempotencyKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}idempotency_key'])!,
      empresaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}empresa_id'])!,
      usuarioId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}usuario_id'])!,
      instalacionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}instalacion_id'])!,
      tipoEntidad: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tipo_entidad'])!,
      entidadId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entidad_id'])!,
      accion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}accion'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      payloadVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}payload_version'])!,
      versionBase: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version_base']),
      creadoEnDispositivo: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}creado_en_dispositivo'])!,
      estado: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}estado'])!,
      motivo: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}motivo']),
      conflictoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}conflicto_id']),
      acknowledged: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}acknowledged'])!,
      intentosRed: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}intentos_red'])!,
      intentosServidor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}intentos_servidor'])!,
      proximoIntentoEn: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}proximo_intento_en']),
      ultimoIntentoEn: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}ultimo_intento_en']),
      ultimoErrorCodigo: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}ultimo_error_codigo']),
      ultimoError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ultimo_error']),
      tomadoPor: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tomado_por']),
      tomadoHasta: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}tomado_hasta']),
      sincronizadoEn: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}sincronizado_en']),
      versionResultante: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version_resultante']),
      rechazoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rechazo_id']),
    );
  }

  @override
  SyncPendientes createAlias(String alias) {
    return SyncPendientes(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class SyncPendientesData extends DataClass
    implements Insertable<SyncPendientesData> {
  final int secuencia;
  final String id;
  final String idempotencyKey;
  final String empresaId;
  final String usuarioId;
  final String instalacionId;
  final String tipoEntidad;
  final String entidadId;
  final String accion;
  final String payload;
  final int payloadVersion;
  final int? versionBase;
  final DateTime creadoEnDispositivo;
  final String estado;
  final String? motivo;
  final String? conflictoId;
  final bool acknowledged;
  final int intentosRed;
  final int intentosServidor;
  final DateTime? proximoIntentoEn;
  final DateTime? ultimoIntentoEn;
  final int? ultimoErrorCodigo;
  final String? ultimoError;
  final String? tomadoPor;
  final DateTime? tomadoHasta;
  final DateTime? sincronizadoEn;
  final int? versionResultante;
  final String? rechazoId;
  const SyncPendientesData(
      {required this.secuencia,
      required this.id,
      required this.idempotencyKey,
      required this.empresaId,
      required this.usuarioId,
      required this.instalacionId,
      required this.tipoEntidad,
      required this.entidadId,
      required this.accion,
      required this.payload,
      required this.payloadVersion,
      this.versionBase,
      required this.creadoEnDispositivo,
      required this.estado,
      this.motivo,
      this.conflictoId,
      required this.acknowledged,
      required this.intentosRed,
      required this.intentosServidor,
      this.proximoIntentoEn,
      this.ultimoIntentoEn,
      this.ultimoErrorCodigo,
      this.ultimoError,
      this.tomadoPor,
      this.tomadoHasta,
      this.sincronizadoEn,
      this.versionResultante,
      this.rechazoId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['secuencia'] = Variable<int>(secuencia);
    map['id'] = Variable<String>(id);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['empresa_id'] = Variable<String>(empresaId);
    map['usuario_id'] = Variable<String>(usuarioId);
    map['instalacion_id'] = Variable<String>(instalacionId);
    map['tipo_entidad'] = Variable<String>(tipoEntidad);
    map['entidad_id'] = Variable<String>(entidadId);
    map['accion'] = Variable<String>(accion);
    map['payload'] = Variable<String>(payload);
    map['payload_version'] = Variable<int>(payloadVersion);
    if (!nullToAbsent || versionBase != null) {
      map['version_base'] = Variable<int>(versionBase);
    }
    map['creado_en_dispositivo'] = Variable<DateTime>(creadoEnDispositivo);
    map['estado'] = Variable<String>(estado);
    if (!nullToAbsent || motivo != null) {
      map['motivo'] = Variable<String>(motivo);
    }
    if (!nullToAbsent || conflictoId != null) {
      map['conflicto_id'] = Variable<String>(conflictoId);
    }
    map['acknowledged'] = Variable<bool>(acknowledged);
    map['intentos_red'] = Variable<int>(intentosRed);
    map['intentos_servidor'] = Variable<int>(intentosServidor);
    if (!nullToAbsent || proximoIntentoEn != null) {
      map['proximo_intento_en'] = Variable<DateTime>(proximoIntentoEn);
    }
    if (!nullToAbsent || ultimoIntentoEn != null) {
      map['ultimo_intento_en'] = Variable<DateTime>(ultimoIntentoEn);
    }
    if (!nullToAbsent || ultimoErrorCodigo != null) {
      map['ultimo_error_codigo'] = Variable<int>(ultimoErrorCodigo);
    }
    if (!nullToAbsent || ultimoError != null) {
      map['ultimo_error'] = Variable<String>(ultimoError);
    }
    if (!nullToAbsent || tomadoPor != null) {
      map['tomado_por'] = Variable<String>(tomadoPor);
    }
    if (!nullToAbsent || tomadoHasta != null) {
      map['tomado_hasta'] = Variable<DateTime>(tomadoHasta);
    }
    if (!nullToAbsent || sincronizadoEn != null) {
      map['sincronizado_en'] = Variable<DateTime>(sincronizadoEn);
    }
    if (!nullToAbsent || versionResultante != null) {
      map['version_resultante'] = Variable<int>(versionResultante);
    }
    if (!nullToAbsent || rechazoId != null) {
      map['rechazo_id'] = Variable<String>(rechazoId);
    }
    return map;
  }

  SyncPendientesCompanion toCompanion(bool nullToAbsent) {
    return SyncPendientesCompanion(
      secuencia: Value(secuencia),
      id: Value(id),
      idempotencyKey: Value(idempotencyKey),
      empresaId: Value(empresaId),
      usuarioId: Value(usuarioId),
      instalacionId: Value(instalacionId),
      tipoEntidad: Value(tipoEntidad),
      entidadId: Value(entidadId),
      accion: Value(accion),
      payload: Value(payload),
      payloadVersion: Value(payloadVersion),
      versionBase: versionBase == null && nullToAbsent
          ? const Value.absent()
          : Value(versionBase),
      creadoEnDispositivo: Value(creadoEnDispositivo),
      estado: Value(estado),
      motivo:
          motivo == null && nullToAbsent ? const Value.absent() : Value(motivo),
      conflictoId: conflictoId == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictoId),
      acknowledged: Value(acknowledged),
      intentosRed: Value(intentosRed),
      intentosServidor: Value(intentosServidor),
      proximoIntentoEn: proximoIntentoEn == null && nullToAbsent
          ? const Value.absent()
          : Value(proximoIntentoEn),
      ultimoIntentoEn: ultimoIntentoEn == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimoIntentoEn),
      ultimoErrorCodigo: ultimoErrorCodigo == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimoErrorCodigo),
      ultimoError: ultimoError == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimoError),
      tomadoPor: tomadoPor == null && nullToAbsent
          ? const Value.absent()
          : Value(tomadoPor),
      tomadoHasta: tomadoHasta == null && nullToAbsent
          ? const Value.absent()
          : Value(tomadoHasta),
      sincronizadoEn: sincronizadoEn == null && nullToAbsent
          ? const Value.absent()
          : Value(sincronizadoEn),
      versionResultante: versionResultante == null && nullToAbsent
          ? const Value.absent()
          : Value(versionResultante),
      rechazoId: rechazoId == null && nullToAbsent
          ? const Value.absent()
          : Value(rechazoId),
    );
  }

  factory SyncPendientesData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPendientesData(
      secuencia: serializer.fromJson<int>(json['secuencia']),
      id: serializer.fromJson<String>(json['id']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      empresaId: serializer.fromJson<String>(json['empresaId']),
      usuarioId: serializer.fromJson<String>(json['usuarioId']),
      instalacionId: serializer.fromJson<String>(json['instalacionId']),
      tipoEntidad: serializer.fromJson<String>(json['tipoEntidad']),
      entidadId: serializer.fromJson<String>(json['entidadId']),
      accion: serializer.fromJson<String>(json['accion']),
      payload: serializer.fromJson<String>(json['payload']),
      payloadVersion: serializer.fromJson<int>(json['payloadVersion']),
      versionBase: serializer.fromJson<int?>(json['versionBase']),
      creadoEnDispositivo:
          serializer.fromJson<DateTime>(json['creadoEnDispositivo']),
      estado: serializer.fromJson<String>(json['estado']),
      motivo: serializer.fromJson<String?>(json['motivo']),
      conflictoId: serializer.fromJson<String?>(json['conflictoId']),
      acknowledged: serializer.fromJson<bool>(json['acknowledged']),
      intentosRed: serializer.fromJson<int>(json['intentosRed']),
      intentosServidor: serializer.fromJson<int>(json['intentosServidor']),
      proximoIntentoEn:
          serializer.fromJson<DateTime?>(json['proximoIntentoEn']),
      ultimoIntentoEn: serializer.fromJson<DateTime?>(json['ultimoIntentoEn']),
      ultimoErrorCodigo: serializer.fromJson<int?>(json['ultimoErrorCodigo']),
      ultimoError: serializer.fromJson<String?>(json['ultimoError']),
      tomadoPor: serializer.fromJson<String?>(json['tomadoPor']),
      tomadoHasta: serializer.fromJson<DateTime?>(json['tomadoHasta']),
      sincronizadoEn: serializer.fromJson<DateTime?>(json['sincronizadoEn']),
      versionResultante: serializer.fromJson<int?>(json['versionResultante']),
      rechazoId: serializer.fromJson<String?>(json['rechazoId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'secuencia': serializer.toJson<int>(secuencia),
      'id': serializer.toJson<String>(id),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'empresaId': serializer.toJson<String>(empresaId),
      'usuarioId': serializer.toJson<String>(usuarioId),
      'instalacionId': serializer.toJson<String>(instalacionId),
      'tipoEntidad': serializer.toJson<String>(tipoEntidad),
      'entidadId': serializer.toJson<String>(entidadId),
      'accion': serializer.toJson<String>(accion),
      'payload': serializer.toJson<String>(payload),
      'payloadVersion': serializer.toJson<int>(payloadVersion),
      'versionBase': serializer.toJson<int?>(versionBase),
      'creadoEnDispositivo': serializer.toJson<DateTime>(creadoEnDispositivo),
      'estado': serializer.toJson<String>(estado),
      'motivo': serializer.toJson<String?>(motivo),
      'conflictoId': serializer.toJson<String?>(conflictoId),
      'acknowledged': serializer.toJson<bool>(acknowledged),
      'intentosRed': serializer.toJson<int>(intentosRed),
      'intentosServidor': serializer.toJson<int>(intentosServidor),
      'proximoIntentoEn': serializer.toJson<DateTime?>(proximoIntentoEn),
      'ultimoIntentoEn': serializer.toJson<DateTime?>(ultimoIntentoEn),
      'ultimoErrorCodigo': serializer.toJson<int?>(ultimoErrorCodigo),
      'ultimoError': serializer.toJson<String?>(ultimoError),
      'tomadoPor': serializer.toJson<String?>(tomadoPor),
      'tomadoHasta': serializer.toJson<DateTime?>(tomadoHasta),
      'sincronizadoEn': serializer.toJson<DateTime?>(sincronizadoEn),
      'versionResultante': serializer.toJson<int?>(versionResultante),
      'rechazoId': serializer.toJson<String?>(rechazoId),
    };
  }

  SyncPendientesData copyWith(
          {int? secuencia,
          String? id,
          String? idempotencyKey,
          String? empresaId,
          String? usuarioId,
          String? instalacionId,
          String? tipoEntidad,
          String? entidadId,
          String? accion,
          String? payload,
          int? payloadVersion,
          Value<int?> versionBase = const Value.absent(),
          DateTime? creadoEnDispositivo,
          String? estado,
          Value<String?> motivo = const Value.absent(),
          Value<String?> conflictoId = const Value.absent(),
          bool? acknowledged,
          int? intentosRed,
          int? intentosServidor,
          Value<DateTime?> proximoIntentoEn = const Value.absent(),
          Value<DateTime?> ultimoIntentoEn = const Value.absent(),
          Value<int?> ultimoErrorCodigo = const Value.absent(),
          Value<String?> ultimoError = const Value.absent(),
          Value<String?> tomadoPor = const Value.absent(),
          Value<DateTime?> tomadoHasta = const Value.absent(),
          Value<DateTime?> sincronizadoEn = const Value.absent(),
          Value<int?> versionResultante = const Value.absent(),
          Value<String?> rechazoId = const Value.absent()}) =>
      SyncPendientesData(
        secuencia: secuencia ?? this.secuencia,
        id: id ?? this.id,
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        empresaId: empresaId ?? this.empresaId,
        usuarioId: usuarioId ?? this.usuarioId,
        instalacionId: instalacionId ?? this.instalacionId,
        tipoEntidad: tipoEntidad ?? this.tipoEntidad,
        entidadId: entidadId ?? this.entidadId,
        accion: accion ?? this.accion,
        payload: payload ?? this.payload,
        payloadVersion: payloadVersion ?? this.payloadVersion,
        versionBase: versionBase.present ? versionBase.value : this.versionBase,
        creadoEnDispositivo: creadoEnDispositivo ?? this.creadoEnDispositivo,
        estado: estado ?? this.estado,
        motivo: motivo.present ? motivo.value : this.motivo,
        conflictoId: conflictoId.present ? conflictoId.value : this.conflictoId,
        acknowledged: acknowledged ?? this.acknowledged,
        intentosRed: intentosRed ?? this.intentosRed,
        intentosServidor: intentosServidor ?? this.intentosServidor,
        proximoIntentoEn: proximoIntentoEn.present
            ? proximoIntentoEn.value
            : this.proximoIntentoEn,
        ultimoIntentoEn: ultimoIntentoEn.present
            ? ultimoIntentoEn.value
            : this.ultimoIntentoEn,
        ultimoErrorCodigo: ultimoErrorCodigo.present
            ? ultimoErrorCodigo.value
            : this.ultimoErrorCodigo,
        ultimoError: ultimoError.present ? ultimoError.value : this.ultimoError,
        tomadoPor: tomadoPor.present ? tomadoPor.value : this.tomadoPor,
        tomadoHasta: tomadoHasta.present ? tomadoHasta.value : this.tomadoHasta,
        sincronizadoEn:
            sincronizadoEn.present ? sincronizadoEn.value : this.sincronizadoEn,
        versionResultante: versionResultante.present
            ? versionResultante.value
            : this.versionResultante,
        rechazoId: rechazoId.present ? rechazoId.value : this.rechazoId,
      );
  SyncPendientesData copyWithCompanion(SyncPendientesCompanion data) {
    return SyncPendientesData(
      secuencia: data.secuencia.present ? data.secuencia.value : this.secuencia,
      id: data.id.present ? data.id.value : this.id,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      empresaId: data.empresaId.present ? data.empresaId.value : this.empresaId,
      usuarioId: data.usuarioId.present ? data.usuarioId.value : this.usuarioId,
      instalacionId: data.instalacionId.present
          ? data.instalacionId.value
          : this.instalacionId,
      tipoEntidad:
          data.tipoEntidad.present ? data.tipoEntidad.value : this.tipoEntidad,
      entidadId: data.entidadId.present ? data.entidadId.value : this.entidadId,
      accion: data.accion.present ? data.accion.value : this.accion,
      payload: data.payload.present ? data.payload.value : this.payload,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      versionBase:
          data.versionBase.present ? data.versionBase.value : this.versionBase,
      creadoEnDispositivo: data.creadoEnDispositivo.present
          ? data.creadoEnDispositivo.value
          : this.creadoEnDispositivo,
      estado: data.estado.present ? data.estado.value : this.estado,
      motivo: data.motivo.present ? data.motivo.value : this.motivo,
      conflictoId:
          data.conflictoId.present ? data.conflictoId.value : this.conflictoId,
      acknowledged: data.acknowledged.present
          ? data.acknowledged.value
          : this.acknowledged,
      intentosRed:
          data.intentosRed.present ? data.intentosRed.value : this.intentosRed,
      intentosServidor: data.intentosServidor.present
          ? data.intentosServidor.value
          : this.intentosServidor,
      proximoIntentoEn: data.proximoIntentoEn.present
          ? data.proximoIntentoEn.value
          : this.proximoIntentoEn,
      ultimoIntentoEn: data.ultimoIntentoEn.present
          ? data.ultimoIntentoEn.value
          : this.ultimoIntentoEn,
      ultimoErrorCodigo: data.ultimoErrorCodigo.present
          ? data.ultimoErrorCodigo.value
          : this.ultimoErrorCodigo,
      ultimoError:
          data.ultimoError.present ? data.ultimoError.value : this.ultimoError,
      tomadoPor: data.tomadoPor.present ? data.tomadoPor.value : this.tomadoPor,
      tomadoHasta:
          data.tomadoHasta.present ? data.tomadoHasta.value : this.tomadoHasta,
      sincronizadoEn: data.sincronizadoEn.present
          ? data.sincronizadoEn.value
          : this.sincronizadoEn,
      versionResultante: data.versionResultante.present
          ? data.versionResultante.value
          : this.versionResultante,
      rechazoId: data.rechazoId.present ? data.rechazoId.value : this.rechazoId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendientesData(')
          ..write('secuencia: $secuencia, ')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('empresaId: $empresaId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('instalacionId: $instalacionId, ')
          ..write('tipoEntidad: $tipoEntidad, ')
          ..write('entidadId: $entidadId, ')
          ..write('accion: $accion, ')
          ..write('payload: $payload, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('versionBase: $versionBase, ')
          ..write('creadoEnDispositivo: $creadoEnDispositivo, ')
          ..write('estado: $estado, ')
          ..write('motivo: $motivo, ')
          ..write('conflictoId: $conflictoId, ')
          ..write('acknowledged: $acknowledged, ')
          ..write('intentosRed: $intentosRed, ')
          ..write('intentosServidor: $intentosServidor, ')
          ..write('proximoIntentoEn: $proximoIntentoEn, ')
          ..write('ultimoIntentoEn: $ultimoIntentoEn, ')
          ..write('ultimoErrorCodigo: $ultimoErrorCodigo, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('tomadoPor: $tomadoPor, ')
          ..write('tomadoHasta: $tomadoHasta, ')
          ..write('sincronizadoEn: $sincronizadoEn, ')
          ..write('versionResultante: $versionResultante, ')
          ..write('rechazoId: $rechazoId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        secuencia,
        id,
        idempotencyKey,
        empresaId,
        usuarioId,
        instalacionId,
        tipoEntidad,
        entidadId,
        accion,
        payload,
        payloadVersion,
        versionBase,
        creadoEnDispositivo,
        estado,
        motivo,
        conflictoId,
        acknowledged,
        intentosRed,
        intentosServidor,
        proximoIntentoEn,
        ultimoIntentoEn,
        ultimoErrorCodigo,
        ultimoError,
        tomadoPor,
        tomadoHasta,
        sincronizadoEn,
        versionResultante,
        rechazoId
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPendientesData &&
          other.secuencia == this.secuencia &&
          other.id == this.id &&
          other.idempotencyKey == this.idempotencyKey &&
          other.empresaId == this.empresaId &&
          other.usuarioId == this.usuarioId &&
          other.instalacionId == this.instalacionId &&
          other.tipoEntidad == this.tipoEntidad &&
          other.entidadId == this.entidadId &&
          other.accion == this.accion &&
          other.payload == this.payload &&
          other.payloadVersion == this.payloadVersion &&
          other.versionBase == this.versionBase &&
          other.creadoEnDispositivo == this.creadoEnDispositivo &&
          other.estado == this.estado &&
          other.motivo == this.motivo &&
          other.conflictoId == this.conflictoId &&
          other.acknowledged == this.acknowledged &&
          other.intentosRed == this.intentosRed &&
          other.intentosServidor == this.intentosServidor &&
          other.proximoIntentoEn == this.proximoIntentoEn &&
          other.ultimoIntentoEn == this.ultimoIntentoEn &&
          other.ultimoErrorCodigo == this.ultimoErrorCodigo &&
          other.ultimoError == this.ultimoError &&
          other.tomadoPor == this.tomadoPor &&
          other.tomadoHasta == this.tomadoHasta &&
          other.sincronizadoEn == this.sincronizadoEn &&
          other.versionResultante == this.versionResultante &&
          other.rechazoId == this.rechazoId);
}

class SyncPendientesCompanion extends UpdateCompanion<SyncPendientesData> {
  final Value<int> secuencia;
  final Value<String> id;
  final Value<String> idempotencyKey;
  final Value<String> empresaId;
  final Value<String> usuarioId;
  final Value<String> instalacionId;
  final Value<String> tipoEntidad;
  final Value<String> entidadId;
  final Value<String> accion;
  final Value<String> payload;
  final Value<int> payloadVersion;
  final Value<int?> versionBase;
  final Value<DateTime> creadoEnDispositivo;
  final Value<String> estado;
  final Value<String?> motivo;
  final Value<String?> conflictoId;
  final Value<bool> acknowledged;
  final Value<int> intentosRed;
  final Value<int> intentosServidor;
  final Value<DateTime?> proximoIntentoEn;
  final Value<DateTime?> ultimoIntentoEn;
  final Value<int?> ultimoErrorCodigo;
  final Value<String?> ultimoError;
  final Value<String?> tomadoPor;
  final Value<DateTime?> tomadoHasta;
  final Value<DateTime?> sincronizadoEn;
  final Value<int?> versionResultante;
  final Value<String?> rechazoId;
  const SyncPendientesCompanion({
    this.secuencia = const Value.absent(),
    this.id = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.usuarioId = const Value.absent(),
    this.instalacionId = const Value.absent(),
    this.tipoEntidad = const Value.absent(),
    this.entidadId = const Value.absent(),
    this.accion = const Value.absent(),
    this.payload = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.versionBase = const Value.absent(),
    this.creadoEnDispositivo = const Value.absent(),
    this.estado = const Value.absent(),
    this.motivo = const Value.absent(),
    this.conflictoId = const Value.absent(),
    this.acknowledged = const Value.absent(),
    this.intentosRed = const Value.absent(),
    this.intentosServidor = const Value.absent(),
    this.proximoIntentoEn = const Value.absent(),
    this.ultimoIntentoEn = const Value.absent(),
    this.ultimoErrorCodigo = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.tomadoPor = const Value.absent(),
    this.tomadoHasta = const Value.absent(),
    this.sincronizadoEn = const Value.absent(),
    this.versionResultante = const Value.absent(),
    this.rechazoId = const Value.absent(),
  });
  SyncPendientesCompanion.insert({
    this.secuencia = const Value.absent(),
    required String id,
    required String idempotencyKey,
    required String empresaId,
    required String usuarioId,
    required String instalacionId,
    required String tipoEntidad,
    required String entidadId,
    required String accion,
    required String payload,
    required int payloadVersion,
    this.versionBase = const Value.absent(),
    required DateTime creadoEnDispositivo,
    this.estado = const Value.absent(),
    this.motivo = const Value.absent(),
    this.conflictoId = const Value.absent(),
    this.acknowledged = const Value.absent(),
    this.intentosRed = const Value.absent(),
    this.intentosServidor = const Value.absent(),
    this.proximoIntentoEn = const Value.absent(),
    this.ultimoIntentoEn = const Value.absent(),
    this.ultimoErrorCodigo = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.tomadoPor = const Value.absent(),
    this.tomadoHasta = const Value.absent(),
    this.sincronizadoEn = const Value.absent(),
    this.versionResultante = const Value.absent(),
    this.rechazoId = const Value.absent(),
  })  : id = Value(id),
        idempotencyKey = Value(idempotencyKey),
        empresaId = Value(empresaId),
        usuarioId = Value(usuarioId),
        instalacionId = Value(instalacionId),
        tipoEntidad = Value(tipoEntidad),
        entidadId = Value(entidadId),
        accion = Value(accion),
        payload = Value(payload),
        payloadVersion = Value(payloadVersion),
        creadoEnDispositivo = Value(creadoEnDispositivo);
  static Insertable<SyncPendientesData> custom({
    Expression<int>? secuencia,
    Expression<String>? id,
    Expression<String>? idempotencyKey,
    Expression<String>? empresaId,
    Expression<String>? usuarioId,
    Expression<String>? instalacionId,
    Expression<String>? tipoEntidad,
    Expression<String>? entidadId,
    Expression<String>? accion,
    Expression<String>? payload,
    Expression<int>? payloadVersion,
    Expression<int>? versionBase,
    Expression<DateTime>? creadoEnDispositivo,
    Expression<String>? estado,
    Expression<String>? motivo,
    Expression<String>? conflictoId,
    Expression<bool>? acknowledged,
    Expression<int>? intentosRed,
    Expression<int>? intentosServidor,
    Expression<DateTime>? proximoIntentoEn,
    Expression<DateTime>? ultimoIntentoEn,
    Expression<int>? ultimoErrorCodigo,
    Expression<String>? ultimoError,
    Expression<String>? tomadoPor,
    Expression<DateTime>? tomadoHasta,
    Expression<DateTime>? sincronizadoEn,
    Expression<int>? versionResultante,
    Expression<String>? rechazoId,
  }) {
    return RawValuesInsertable({
      if (secuencia != null) 'secuencia': secuencia,
      if (id != null) 'id': id,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (empresaId != null) 'empresa_id': empresaId,
      if (usuarioId != null) 'usuario_id': usuarioId,
      if (instalacionId != null) 'instalacion_id': instalacionId,
      if (tipoEntidad != null) 'tipo_entidad': tipoEntidad,
      if (entidadId != null) 'entidad_id': entidadId,
      if (accion != null) 'accion': accion,
      if (payload != null) 'payload': payload,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (versionBase != null) 'version_base': versionBase,
      if (creadoEnDispositivo != null)
        'creado_en_dispositivo': creadoEnDispositivo,
      if (estado != null) 'estado': estado,
      if (motivo != null) 'motivo': motivo,
      if (conflictoId != null) 'conflicto_id': conflictoId,
      if (acknowledged != null) 'acknowledged': acknowledged,
      if (intentosRed != null) 'intentos_red': intentosRed,
      if (intentosServidor != null) 'intentos_servidor': intentosServidor,
      if (proximoIntentoEn != null) 'proximo_intento_en': proximoIntentoEn,
      if (ultimoIntentoEn != null) 'ultimo_intento_en': ultimoIntentoEn,
      if (ultimoErrorCodigo != null) 'ultimo_error_codigo': ultimoErrorCodigo,
      if (ultimoError != null) 'ultimo_error': ultimoError,
      if (tomadoPor != null) 'tomado_por': tomadoPor,
      if (tomadoHasta != null) 'tomado_hasta': tomadoHasta,
      if (sincronizadoEn != null) 'sincronizado_en': sincronizadoEn,
      if (versionResultante != null) 'version_resultante': versionResultante,
      if (rechazoId != null) 'rechazo_id': rechazoId,
    });
  }

  SyncPendientesCompanion copyWith(
      {Value<int>? secuencia,
      Value<String>? id,
      Value<String>? idempotencyKey,
      Value<String>? empresaId,
      Value<String>? usuarioId,
      Value<String>? instalacionId,
      Value<String>? tipoEntidad,
      Value<String>? entidadId,
      Value<String>? accion,
      Value<String>? payload,
      Value<int>? payloadVersion,
      Value<int?>? versionBase,
      Value<DateTime>? creadoEnDispositivo,
      Value<String>? estado,
      Value<String?>? motivo,
      Value<String?>? conflictoId,
      Value<bool>? acknowledged,
      Value<int>? intentosRed,
      Value<int>? intentosServidor,
      Value<DateTime?>? proximoIntentoEn,
      Value<DateTime?>? ultimoIntentoEn,
      Value<int?>? ultimoErrorCodigo,
      Value<String?>? ultimoError,
      Value<String?>? tomadoPor,
      Value<DateTime?>? tomadoHasta,
      Value<DateTime?>? sincronizadoEn,
      Value<int?>? versionResultante,
      Value<String?>? rechazoId}) {
    return SyncPendientesCompanion(
      secuencia: secuencia ?? this.secuencia,
      id: id ?? this.id,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      empresaId: empresaId ?? this.empresaId,
      usuarioId: usuarioId ?? this.usuarioId,
      instalacionId: instalacionId ?? this.instalacionId,
      tipoEntidad: tipoEntidad ?? this.tipoEntidad,
      entidadId: entidadId ?? this.entidadId,
      accion: accion ?? this.accion,
      payload: payload ?? this.payload,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      versionBase: versionBase ?? this.versionBase,
      creadoEnDispositivo: creadoEnDispositivo ?? this.creadoEnDispositivo,
      estado: estado ?? this.estado,
      motivo: motivo ?? this.motivo,
      conflictoId: conflictoId ?? this.conflictoId,
      acknowledged: acknowledged ?? this.acknowledged,
      intentosRed: intentosRed ?? this.intentosRed,
      intentosServidor: intentosServidor ?? this.intentosServidor,
      proximoIntentoEn: proximoIntentoEn ?? this.proximoIntentoEn,
      ultimoIntentoEn: ultimoIntentoEn ?? this.ultimoIntentoEn,
      ultimoErrorCodigo: ultimoErrorCodigo ?? this.ultimoErrorCodigo,
      ultimoError: ultimoError ?? this.ultimoError,
      tomadoPor: tomadoPor ?? this.tomadoPor,
      tomadoHasta: tomadoHasta ?? this.tomadoHasta,
      sincronizadoEn: sincronizadoEn ?? this.sincronizadoEn,
      versionResultante: versionResultante ?? this.versionResultante,
      rechazoId: rechazoId ?? this.rechazoId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (secuencia.present) {
      map['secuencia'] = Variable<int>(secuencia.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (empresaId.present) {
      map['empresa_id'] = Variable<String>(empresaId.value);
    }
    if (usuarioId.present) {
      map['usuario_id'] = Variable<String>(usuarioId.value);
    }
    if (instalacionId.present) {
      map['instalacion_id'] = Variable<String>(instalacionId.value);
    }
    if (tipoEntidad.present) {
      map['tipo_entidad'] = Variable<String>(tipoEntidad.value);
    }
    if (entidadId.present) {
      map['entidad_id'] = Variable<String>(entidadId.value);
    }
    if (accion.present) {
      map['accion'] = Variable<String>(accion.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (versionBase.present) {
      map['version_base'] = Variable<int>(versionBase.value);
    }
    if (creadoEnDispositivo.present) {
      map['creado_en_dispositivo'] =
          Variable<DateTime>(creadoEnDispositivo.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (motivo.present) {
      map['motivo'] = Variable<String>(motivo.value);
    }
    if (conflictoId.present) {
      map['conflicto_id'] = Variable<String>(conflictoId.value);
    }
    if (acknowledged.present) {
      map['acknowledged'] = Variable<bool>(acknowledged.value);
    }
    if (intentosRed.present) {
      map['intentos_red'] = Variable<int>(intentosRed.value);
    }
    if (intentosServidor.present) {
      map['intentos_servidor'] = Variable<int>(intentosServidor.value);
    }
    if (proximoIntentoEn.present) {
      map['proximo_intento_en'] = Variable<DateTime>(proximoIntentoEn.value);
    }
    if (ultimoIntentoEn.present) {
      map['ultimo_intento_en'] = Variable<DateTime>(ultimoIntentoEn.value);
    }
    if (ultimoErrorCodigo.present) {
      map['ultimo_error_codigo'] = Variable<int>(ultimoErrorCodigo.value);
    }
    if (ultimoError.present) {
      map['ultimo_error'] = Variable<String>(ultimoError.value);
    }
    if (tomadoPor.present) {
      map['tomado_por'] = Variable<String>(tomadoPor.value);
    }
    if (tomadoHasta.present) {
      map['tomado_hasta'] = Variable<DateTime>(tomadoHasta.value);
    }
    if (sincronizadoEn.present) {
      map['sincronizado_en'] = Variable<DateTime>(sincronizadoEn.value);
    }
    if (versionResultante.present) {
      map['version_resultante'] = Variable<int>(versionResultante.value);
    }
    if (rechazoId.present) {
      map['rechazo_id'] = Variable<String>(rechazoId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendientesCompanion(')
          ..write('secuencia: $secuencia, ')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('empresaId: $empresaId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('instalacionId: $instalacionId, ')
          ..write('tipoEntidad: $tipoEntidad, ')
          ..write('entidadId: $entidadId, ')
          ..write('accion: $accion, ')
          ..write('payload: $payload, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('versionBase: $versionBase, ')
          ..write('creadoEnDispositivo: $creadoEnDispositivo, ')
          ..write('estado: $estado, ')
          ..write('motivo: $motivo, ')
          ..write('conflictoId: $conflictoId, ')
          ..write('acknowledged: $acknowledged, ')
          ..write('intentosRed: $intentosRed, ')
          ..write('intentosServidor: $intentosServidor, ')
          ..write('proximoIntentoEn: $proximoIntentoEn, ')
          ..write('ultimoIntentoEn: $ultimoIntentoEn, ')
          ..write('ultimoErrorCodigo: $ultimoErrorCodigo, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('tomadoPor: $tomadoPor, ')
          ..write('tomadoHasta: $tomadoHasta, ')
          ..write('sincronizadoEn: $sincronizadoEn, ')
          ..write('versionResultante: $versionResultante, ')
          ..write('rechazoId: $rechazoId')
          ..write(')'))
        .toString();
  }
}

class ItemsCache extends Table with TableInfo<ItemsCache, ItemsCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ItemsCache(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> proyectoId = GeneratedColumn<String>(
      'proyecto_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> proyectoNombre = GeneratedColumn<String>(
      'proyecto_nombre', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<String> parentItemId = GeneratedColumn<String>(
      'parent_item_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> nivelProfundidad = GeneratedColumn<int>(
      'nivel_profundidad', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
      'nombre', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> descripcion = GeneratedColumn<String>(
      'descripcion', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> asignadoA = GeneratedColumn<String>(
      'asignado_a', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
      'estado', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> estadoPrevio = GeneratedColumn<String>(
      'estado_previo', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<bool> tieneConflicto = GeneratedColumn<bool>(
      'tiene_conflicto', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("tiene_conflicto" IN (0, 1))'),
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> cachadoEn = GeneratedColumn<DateTime>(
      'cachado_en', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        proyectoId,
        proyectoNombre,
        parentItemId,
        nivelProfundidad,
        nombre,
        descripcion,
        asignadoA,
        estado,
        estadoPrevio,
        tieneConflicto,
        updatedAt,
        cachadoEn
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items_cache';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ItemsCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemsCacheData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      proyectoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}proyecto_id'])!,
      proyectoNombre: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}proyecto_nombre'])!,
      parentItemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_item_id']),
      nivelProfundidad: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}nivel_profundidad'])!,
      nombre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}nombre'])!,
      descripcion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}descripcion']),
      asignadoA: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}asignado_a']),
      estado: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}estado'])!,
      estadoPrevio: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}estado_previo']),
      tieneConflicto: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}tiene_conflicto'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      cachadoEn: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cachado_en'])!,
    );
  }

  @override
  ItemsCache createAlias(String alias) {
    return ItemsCache(attachedDatabase, alias);
  }
}

class ItemsCacheData extends DataClass implements Insertable<ItemsCacheData> {
  final String id;
  final String proyectoId;
  final String proyectoNombre;
  final String? parentItemId;
  final int nivelProfundidad;
  final String nombre;
  final String? descripcion;
  final String? asignadoA;
  final String estado;
  final String? estadoPrevio;
  final bool tieneConflicto;
  final DateTime updatedAt;
  final DateTime cachadoEn;
  const ItemsCacheData(
      {required this.id,
      required this.proyectoId,
      required this.proyectoNombre,
      this.parentItemId,
      required this.nivelProfundidad,
      required this.nombre,
      this.descripcion,
      this.asignadoA,
      required this.estado,
      this.estadoPrevio,
      required this.tieneConflicto,
      required this.updatedAt,
      required this.cachadoEn});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['proyecto_id'] = Variable<String>(proyectoId);
    map['proyecto_nombre'] = Variable<String>(proyectoNombre);
    if (!nullToAbsent || parentItemId != null) {
      map['parent_item_id'] = Variable<String>(parentItemId);
    }
    map['nivel_profundidad'] = Variable<int>(nivelProfundidad);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || descripcion != null) {
      map['descripcion'] = Variable<String>(descripcion);
    }
    if (!nullToAbsent || asignadoA != null) {
      map['asignado_a'] = Variable<String>(asignadoA);
    }
    map['estado'] = Variable<String>(estado);
    if (!nullToAbsent || estadoPrevio != null) {
      map['estado_previo'] = Variable<String>(estadoPrevio);
    }
    map['tiene_conflicto'] = Variable<bool>(tieneConflicto);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['cachado_en'] = Variable<DateTime>(cachadoEn);
    return map;
  }

  ItemsCacheCompanion toCompanion(bool nullToAbsent) {
    return ItemsCacheCompanion(
      id: Value(id),
      proyectoId: Value(proyectoId),
      proyectoNombre: Value(proyectoNombre),
      parentItemId: parentItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentItemId),
      nivelProfundidad: Value(nivelProfundidad),
      nombre: Value(nombre),
      descripcion: descripcion == null && nullToAbsent
          ? const Value.absent()
          : Value(descripcion),
      asignadoA: asignadoA == null && nullToAbsent
          ? const Value.absent()
          : Value(asignadoA),
      estado: Value(estado),
      estadoPrevio: estadoPrevio == null && nullToAbsent
          ? const Value.absent()
          : Value(estadoPrevio),
      tieneConflicto: Value(tieneConflicto),
      updatedAt: Value(updatedAt),
      cachadoEn: Value(cachadoEn),
    );
  }

  factory ItemsCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemsCacheData(
      id: serializer.fromJson<String>(json['id']),
      proyectoId: serializer.fromJson<String>(json['proyectoId']),
      proyectoNombre: serializer.fromJson<String>(json['proyectoNombre']),
      parentItemId: serializer.fromJson<String?>(json['parentItemId']),
      nivelProfundidad: serializer.fromJson<int>(json['nivelProfundidad']),
      nombre: serializer.fromJson<String>(json['nombre']),
      descripcion: serializer.fromJson<String?>(json['descripcion']),
      asignadoA: serializer.fromJson<String?>(json['asignadoA']),
      estado: serializer.fromJson<String>(json['estado']),
      estadoPrevio: serializer.fromJson<String?>(json['estadoPrevio']),
      tieneConflicto: serializer.fromJson<bool>(json['tieneConflicto']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      cachadoEn: serializer.fromJson<DateTime>(json['cachadoEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'proyectoId': serializer.toJson<String>(proyectoId),
      'proyectoNombre': serializer.toJson<String>(proyectoNombre),
      'parentItemId': serializer.toJson<String?>(parentItemId),
      'nivelProfundidad': serializer.toJson<int>(nivelProfundidad),
      'nombre': serializer.toJson<String>(nombre),
      'descripcion': serializer.toJson<String?>(descripcion),
      'asignadoA': serializer.toJson<String?>(asignadoA),
      'estado': serializer.toJson<String>(estado),
      'estadoPrevio': serializer.toJson<String?>(estadoPrevio),
      'tieneConflicto': serializer.toJson<bool>(tieneConflicto),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'cachadoEn': serializer.toJson<DateTime>(cachadoEn),
    };
  }

  ItemsCacheData copyWith(
          {String? id,
          String? proyectoId,
          String? proyectoNombre,
          Value<String?> parentItemId = const Value.absent(),
          int? nivelProfundidad,
          String? nombre,
          Value<String?> descripcion = const Value.absent(),
          Value<String?> asignadoA = const Value.absent(),
          String? estado,
          Value<String?> estadoPrevio = const Value.absent(),
          bool? tieneConflicto,
          DateTime? updatedAt,
          DateTime? cachadoEn}) =>
      ItemsCacheData(
        id: id ?? this.id,
        proyectoId: proyectoId ?? this.proyectoId,
        proyectoNombre: proyectoNombre ?? this.proyectoNombre,
        parentItemId:
            parentItemId.present ? parentItemId.value : this.parentItemId,
        nivelProfundidad: nivelProfundidad ?? this.nivelProfundidad,
        nombre: nombre ?? this.nombre,
        descripcion: descripcion.present ? descripcion.value : this.descripcion,
        asignadoA: asignadoA.present ? asignadoA.value : this.asignadoA,
        estado: estado ?? this.estado,
        estadoPrevio:
            estadoPrevio.present ? estadoPrevio.value : this.estadoPrevio,
        tieneConflicto: tieneConflicto ?? this.tieneConflicto,
        updatedAt: updatedAt ?? this.updatedAt,
        cachadoEn: cachadoEn ?? this.cachadoEn,
      );
  ItemsCacheData copyWithCompanion(ItemsCacheCompanion data) {
    return ItemsCacheData(
      id: data.id.present ? data.id.value : this.id,
      proyectoId:
          data.proyectoId.present ? data.proyectoId.value : this.proyectoId,
      proyectoNombre: data.proyectoNombre.present
          ? data.proyectoNombre.value
          : this.proyectoNombre,
      parentItemId: data.parentItemId.present
          ? data.parentItemId.value
          : this.parentItemId,
      nivelProfundidad: data.nivelProfundidad.present
          ? data.nivelProfundidad.value
          : this.nivelProfundidad,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      descripcion:
          data.descripcion.present ? data.descripcion.value : this.descripcion,
      asignadoA: data.asignadoA.present ? data.asignadoA.value : this.asignadoA,
      estado: data.estado.present ? data.estado.value : this.estado,
      estadoPrevio: data.estadoPrevio.present
          ? data.estadoPrevio.value
          : this.estadoPrevio,
      tieneConflicto: data.tieneConflicto.present
          ? data.tieneConflicto.value
          : this.tieneConflicto,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cachadoEn: data.cachadoEn.present ? data.cachadoEn.value : this.cachadoEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCacheData(')
          ..write('id: $id, ')
          ..write('proyectoId: $proyectoId, ')
          ..write('proyectoNombre: $proyectoNombre, ')
          ..write('parentItemId: $parentItemId, ')
          ..write('nivelProfundidad: $nivelProfundidad, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('asignadoA: $asignadoA, ')
          ..write('estado: $estado, ')
          ..write('estadoPrevio: $estadoPrevio, ')
          ..write('tieneConflicto: $tieneConflicto, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cachadoEn: $cachadoEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      proyectoId,
      proyectoNombre,
      parentItemId,
      nivelProfundidad,
      nombre,
      descripcion,
      asignadoA,
      estado,
      estadoPrevio,
      tieneConflicto,
      updatedAt,
      cachadoEn);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemsCacheData &&
          other.id == this.id &&
          other.proyectoId == this.proyectoId &&
          other.proyectoNombre == this.proyectoNombre &&
          other.parentItemId == this.parentItemId &&
          other.nivelProfundidad == this.nivelProfundidad &&
          other.nombre == this.nombre &&
          other.descripcion == this.descripcion &&
          other.asignadoA == this.asignadoA &&
          other.estado == this.estado &&
          other.estadoPrevio == this.estadoPrevio &&
          other.tieneConflicto == this.tieneConflicto &&
          other.updatedAt == this.updatedAt &&
          other.cachadoEn == this.cachadoEn);
}

class ItemsCacheCompanion extends UpdateCompanion<ItemsCacheData> {
  final Value<String> id;
  final Value<String> proyectoId;
  final Value<String> proyectoNombre;
  final Value<String?> parentItemId;
  final Value<int> nivelProfundidad;
  final Value<String> nombre;
  final Value<String?> descripcion;
  final Value<String?> asignadoA;
  final Value<String> estado;
  final Value<String?> estadoPrevio;
  final Value<bool> tieneConflicto;
  final Value<DateTime> updatedAt;
  final Value<DateTime> cachadoEn;
  final Value<int> rowid;
  const ItemsCacheCompanion({
    this.id = const Value.absent(),
    this.proyectoId = const Value.absent(),
    this.proyectoNombre = const Value.absent(),
    this.parentItemId = const Value.absent(),
    this.nivelProfundidad = const Value.absent(),
    this.nombre = const Value.absent(),
    this.descripcion = const Value.absent(),
    this.asignadoA = const Value.absent(),
    this.estado = const Value.absent(),
    this.estadoPrevio = const Value.absent(),
    this.tieneConflicto = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cachadoEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemsCacheCompanion.insert({
    required String id,
    required String proyectoId,
    this.proyectoNombre = const Value.absent(),
    this.parentItemId = const Value.absent(),
    this.nivelProfundidad = const Value.absent(),
    required String nombre,
    this.descripcion = const Value.absent(),
    this.asignadoA = const Value.absent(),
    required String estado,
    this.estadoPrevio = const Value.absent(),
    this.tieneConflicto = const Value.absent(),
    required DateTime updatedAt,
    required DateTime cachadoEn,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        proyectoId = Value(proyectoId),
        nombre = Value(nombre),
        estado = Value(estado),
        updatedAt = Value(updatedAt),
        cachadoEn = Value(cachadoEn);
  static Insertable<ItemsCacheData> custom({
    Expression<String>? id,
    Expression<String>? proyectoId,
    Expression<String>? proyectoNombre,
    Expression<String>? parentItemId,
    Expression<int>? nivelProfundidad,
    Expression<String>? nombre,
    Expression<String>? descripcion,
    Expression<String>? asignadoA,
    Expression<String>? estado,
    Expression<String>? estadoPrevio,
    Expression<bool>? tieneConflicto,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? cachadoEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (proyectoId != null) 'proyecto_id': proyectoId,
      if (proyectoNombre != null) 'proyecto_nombre': proyectoNombre,
      if (parentItemId != null) 'parent_item_id': parentItemId,
      if (nivelProfundidad != null) 'nivel_profundidad': nivelProfundidad,
      if (nombre != null) 'nombre': nombre,
      if (descripcion != null) 'descripcion': descripcion,
      if (asignadoA != null) 'asignado_a': asignadoA,
      if (estado != null) 'estado': estado,
      if (estadoPrevio != null) 'estado_previo': estadoPrevio,
      if (tieneConflicto != null) 'tiene_conflicto': tieneConflicto,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cachadoEn != null) 'cachado_en': cachadoEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemsCacheCompanion copyWith(
      {Value<String>? id,
      Value<String>? proyectoId,
      Value<String>? proyectoNombre,
      Value<String?>? parentItemId,
      Value<int>? nivelProfundidad,
      Value<String>? nombre,
      Value<String?>? descripcion,
      Value<String?>? asignadoA,
      Value<String>? estado,
      Value<String?>? estadoPrevio,
      Value<bool>? tieneConflicto,
      Value<DateTime>? updatedAt,
      Value<DateTime>? cachadoEn,
      Value<int>? rowid}) {
    return ItemsCacheCompanion(
      id: id ?? this.id,
      proyectoId: proyectoId ?? this.proyectoId,
      proyectoNombre: proyectoNombre ?? this.proyectoNombre,
      parentItemId: parentItemId ?? this.parentItemId,
      nivelProfundidad: nivelProfundidad ?? this.nivelProfundidad,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      asignadoA: asignadoA ?? this.asignadoA,
      estado: estado ?? this.estado,
      estadoPrevio: estadoPrevio ?? this.estadoPrevio,
      tieneConflicto: tieneConflicto ?? this.tieneConflicto,
      updatedAt: updatedAt ?? this.updatedAt,
      cachadoEn: cachadoEn ?? this.cachadoEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (proyectoId.present) {
      map['proyecto_id'] = Variable<String>(proyectoId.value);
    }
    if (proyectoNombre.present) {
      map['proyecto_nombre'] = Variable<String>(proyectoNombre.value);
    }
    if (parentItemId.present) {
      map['parent_item_id'] = Variable<String>(parentItemId.value);
    }
    if (nivelProfundidad.present) {
      map['nivel_profundidad'] = Variable<int>(nivelProfundidad.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (descripcion.present) {
      map['descripcion'] = Variable<String>(descripcion.value);
    }
    if (asignadoA.present) {
      map['asignado_a'] = Variable<String>(asignadoA.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (estadoPrevio.present) {
      map['estado_previo'] = Variable<String>(estadoPrevio.value);
    }
    if (tieneConflicto.present) {
      map['tiene_conflicto'] = Variable<bool>(tieneConflicto.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cachadoEn.present) {
      map['cachado_en'] = Variable<DateTime>(cachadoEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCacheCompanion(')
          ..write('id: $id, ')
          ..write('proyectoId: $proyectoId, ')
          ..write('proyectoNombre: $proyectoNombre, ')
          ..write('parentItemId: $parentItemId, ')
          ..write('nivelProfundidad: $nivelProfundidad, ')
          ..write('nombre: $nombre, ')
          ..write('descripcion: $descripcion, ')
          ..write('asignadoA: $asignadoA, ')
          ..write('estado: $estado, ')
          ..write('estadoPrevio: $estadoPrevio, ')
          ..write('tieneConflicto: $tieneConflicto, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cachadoEn: $cachadoEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class UsuarioActivo extends Table
    with TableInfo<UsuarioActivo, UsuarioActivoData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  UsuarioActivo(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> firebaseUid = GeneratedColumn<String>(
      'firebase_uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> nombreCompleto = GeneratedColumn<String>(
      'nombre_completo', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> rolActual = GeneratedColumn<String>(
      'rol_actual', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> empresaId = GeneratedColumn<String>(
      'empresa_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> empresaNombre = GeneratedColumn<String>(
      'empresa_nombre', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<bool> esSuperAdmin = GeneratedColumn<bool>(
      'es_super_admin', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("es_super_admin" IN (0, 1))'),
      defaultValue: const CustomExpression('0'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        firebaseUid,
        nombreCompleto,
        email,
        rolActual,
        empresaId,
        empresaNombre,
        esSuperAdmin
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usuario_activo';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsuarioActivoData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsuarioActivoData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      firebaseUid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}firebase_uid'])!,
      nombreCompleto: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}nombre_completo'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      rolActual: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rol_actual'])!,
      empresaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}empresa_id'])!,
      empresaNombre: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}empresa_nombre'])!,
      esSuperAdmin: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}es_super_admin'])!,
    );
  }

  @override
  UsuarioActivo createAlias(String alias) {
    return UsuarioActivo(attachedDatabase, alias);
  }
}

class UsuarioActivoData extends DataClass
    implements Insertable<UsuarioActivoData> {
  final String id;
  final String firebaseUid;
  final String nombreCompleto;
  final String email;
  final String rolActual;
  final String empresaId;
  final String empresaNombre;
  final bool esSuperAdmin;
  const UsuarioActivoData(
      {required this.id,
      required this.firebaseUid,
      required this.nombreCompleto,
      required this.email,
      required this.rolActual,
      required this.empresaId,
      required this.empresaNombre,
      required this.esSuperAdmin});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['firebase_uid'] = Variable<String>(firebaseUid);
    map['nombre_completo'] = Variable<String>(nombreCompleto);
    map['email'] = Variable<String>(email);
    map['rol_actual'] = Variable<String>(rolActual);
    map['empresa_id'] = Variable<String>(empresaId);
    map['empresa_nombre'] = Variable<String>(empresaNombre);
    map['es_super_admin'] = Variable<bool>(esSuperAdmin);
    return map;
  }

  UsuarioActivoCompanion toCompanion(bool nullToAbsent) {
    return UsuarioActivoCompanion(
      id: Value(id),
      firebaseUid: Value(firebaseUid),
      nombreCompleto: Value(nombreCompleto),
      email: Value(email),
      rolActual: Value(rolActual),
      empresaId: Value(empresaId),
      empresaNombre: Value(empresaNombre),
      esSuperAdmin: Value(esSuperAdmin),
    );
  }

  factory UsuarioActivoData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsuarioActivoData(
      id: serializer.fromJson<String>(json['id']),
      firebaseUid: serializer.fromJson<String>(json['firebaseUid']),
      nombreCompleto: serializer.fromJson<String>(json['nombreCompleto']),
      email: serializer.fromJson<String>(json['email']),
      rolActual: serializer.fromJson<String>(json['rolActual']),
      empresaId: serializer.fromJson<String>(json['empresaId']),
      empresaNombre: serializer.fromJson<String>(json['empresaNombre']),
      esSuperAdmin: serializer.fromJson<bool>(json['esSuperAdmin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'firebaseUid': serializer.toJson<String>(firebaseUid),
      'nombreCompleto': serializer.toJson<String>(nombreCompleto),
      'email': serializer.toJson<String>(email),
      'rolActual': serializer.toJson<String>(rolActual),
      'empresaId': serializer.toJson<String>(empresaId),
      'empresaNombre': serializer.toJson<String>(empresaNombre),
      'esSuperAdmin': serializer.toJson<bool>(esSuperAdmin),
    };
  }

  UsuarioActivoData copyWith(
          {String? id,
          String? firebaseUid,
          String? nombreCompleto,
          String? email,
          String? rolActual,
          String? empresaId,
          String? empresaNombre,
          bool? esSuperAdmin}) =>
      UsuarioActivoData(
        id: id ?? this.id,
        firebaseUid: firebaseUid ?? this.firebaseUid,
        nombreCompleto: nombreCompleto ?? this.nombreCompleto,
        email: email ?? this.email,
        rolActual: rolActual ?? this.rolActual,
        empresaId: empresaId ?? this.empresaId,
        empresaNombre: empresaNombre ?? this.empresaNombre,
        esSuperAdmin: esSuperAdmin ?? this.esSuperAdmin,
      );
  UsuarioActivoData copyWithCompanion(UsuarioActivoCompanion data) {
    return UsuarioActivoData(
      id: data.id.present ? data.id.value : this.id,
      firebaseUid:
          data.firebaseUid.present ? data.firebaseUid.value : this.firebaseUid,
      nombreCompleto: data.nombreCompleto.present
          ? data.nombreCompleto.value
          : this.nombreCompleto,
      email: data.email.present ? data.email.value : this.email,
      rolActual: data.rolActual.present ? data.rolActual.value : this.rolActual,
      empresaId: data.empresaId.present ? data.empresaId.value : this.empresaId,
      empresaNombre: data.empresaNombre.present
          ? data.empresaNombre.value
          : this.empresaNombre,
      esSuperAdmin: data.esSuperAdmin.present
          ? data.esSuperAdmin.value
          : this.esSuperAdmin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsuarioActivoData(')
          ..write('id: $id, ')
          ..write('firebaseUid: $firebaseUid, ')
          ..write('nombreCompleto: $nombreCompleto, ')
          ..write('email: $email, ')
          ..write('rolActual: $rolActual, ')
          ..write('empresaId: $empresaId, ')
          ..write('empresaNombre: $empresaNombre, ')
          ..write('esSuperAdmin: $esSuperAdmin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, firebaseUid, nombreCompleto, email,
      rolActual, empresaId, empresaNombre, esSuperAdmin);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsuarioActivoData &&
          other.id == this.id &&
          other.firebaseUid == this.firebaseUid &&
          other.nombreCompleto == this.nombreCompleto &&
          other.email == this.email &&
          other.rolActual == this.rolActual &&
          other.empresaId == this.empresaId &&
          other.empresaNombre == this.empresaNombre &&
          other.esSuperAdmin == this.esSuperAdmin);
}

class UsuarioActivoCompanion extends UpdateCompanion<UsuarioActivoData> {
  final Value<String> id;
  final Value<String> firebaseUid;
  final Value<String> nombreCompleto;
  final Value<String> email;
  final Value<String> rolActual;
  final Value<String> empresaId;
  final Value<String> empresaNombre;
  final Value<bool> esSuperAdmin;
  final Value<int> rowid;
  const UsuarioActivoCompanion({
    this.id = const Value.absent(),
    this.firebaseUid = const Value.absent(),
    this.nombreCompleto = const Value.absent(),
    this.email = const Value.absent(),
    this.rolActual = const Value.absent(),
    this.empresaId = const Value.absent(),
    this.empresaNombre = const Value.absent(),
    this.esSuperAdmin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsuarioActivoCompanion.insert({
    required String id,
    required String firebaseUid,
    required String nombreCompleto,
    required String email,
    required String rolActual,
    required String empresaId,
    required String empresaNombre,
    this.esSuperAdmin = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        firebaseUid = Value(firebaseUid),
        nombreCompleto = Value(nombreCompleto),
        email = Value(email),
        rolActual = Value(rolActual),
        empresaId = Value(empresaId),
        empresaNombre = Value(empresaNombre);
  static Insertable<UsuarioActivoData> custom({
    Expression<String>? id,
    Expression<String>? firebaseUid,
    Expression<String>? nombreCompleto,
    Expression<String>? email,
    Expression<String>? rolActual,
    Expression<String>? empresaId,
    Expression<String>? empresaNombre,
    Expression<bool>? esSuperAdmin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (firebaseUid != null) 'firebase_uid': firebaseUid,
      if (nombreCompleto != null) 'nombre_completo': nombreCompleto,
      if (email != null) 'email': email,
      if (rolActual != null) 'rol_actual': rolActual,
      if (empresaId != null) 'empresa_id': empresaId,
      if (empresaNombre != null) 'empresa_nombre': empresaNombre,
      if (esSuperAdmin != null) 'es_super_admin': esSuperAdmin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsuarioActivoCompanion copyWith(
      {Value<String>? id,
      Value<String>? firebaseUid,
      Value<String>? nombreCompleto,
      Value<String>? email,
      Value<String>? rolActual,
      Value<String>? empresaId,
      Value<String>? empresaNombre,
      Value<bool>? esSuperAdmin,
      Value<int>? rowid}) {
    return UsuarioActivoCompanion(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      email: email ?? this.email,
      rolActual: rolActual ?? this.rolActual,
      empresaId: empresaId ?? this.empresaId,
      empresaNombre: empresaNombre ?? this.empresaNombre,
      esSuperAdmin: esSuperAdmin ?? this.esSuperAdmin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (firebaseUid.present) {
      map['firebase_uid'] = Variable<String>(firebaseUid.value);
    }
    if (nombreCompleto.present) {
      map['nombre_completo'] = Variable<String>(nombreCompleto.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (rolActual.present) {
      map['rol_actual'] = Variable<String>(rolActual.value);
    }
    if (empresaId.present) {
      map['empresa_id'] = Variable<String>(empresaId.value);
    }
    if (empresaNombre.present) {
      map['empresa_nombre'] = Variable<String>(empresaNombre.value);
    }
    if (esSuperAdmin.present) {
      map['es_super_admin'] = Variable<bool>(esSuperAdmin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsuarioActivoCompanion(')
          ..write('id: $id, ')
          ..write('firebaseUid: $firebaseUid, ')
          ..write('nombreCompleto: $nombreCompleto, ')
          ..write('email: $email, ')
          ..write('rolActual: $rolActual, ')
          ..write('empresaId: $empresaId, ')
          ..write('empresaNombre: $empresaNombre, ')
          ..write('esSuperAdmin: $esSuperAdmin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SyncReconciliacion extends Table
    with TableInfo<SyncReconciliacion, SyncReconciliacionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncReconciliacion(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> ultimaReconciliacion =
      GeneratedColumn<DateTime>('ultima_reconciliacion', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, ultimaReconciliacion];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_reconciliacion';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncReconciliacionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncReconciliacionData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ultimaReconciliacion: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}ultima_reconciliacion']),
    );
  }

  @override
  SyncReconciliacion createAlias(String alias) {
    return SyncReconciliacion(attachedDatabase, alias);
  }
}

class SyncReconciliacionData extends DataClass
    implements Insertable<SyncReconciliacionData> {
  final String id;
  final DateTime? ultimaReconciliacion;
  const SyncReconciliacionData({required this.id, this.ultimaReconciliacion});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || ultimaReconciliacion != null) {
      map['ultima_reconciliacion'] = Variable<DateTime>(ultimaReconciliacion);
    }
    return map;
  }

  SyncReconciliacionCompanion toCompanion(bool nullToAbsent) {
    return SyncReconciliacionCompanion(
      id: Value(id),
      ultimaReconciliacion: ultimaReconciliacion == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimaReconciliacion),
    );
  }

  factory SyncReconciliacionData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncReconciliacionData(
      id: serializer.fromJson<String>(json['id']),
      ultimaReconciliacion:
          serializer.fromJson<DateTime?>(json['ultimaReconciliacion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ultimaReconciliacion':
          serializer.toJson<DateTime?>(ultimaReconciliacion),
    };
  }

  SyncReconciliacionData copyWith(
          {String? id,
          Value<DateTime?> ultimaReconciliacion = const Value.absent()}) =>
      SyncReconciliacionData(
        id: id ?? this.id,
        ultimaReconciliacion: ultimaReconciliacion.present
            ? ultimaReconciliacion.value
            : this.ultimaReconciliacion,
      );
  SyncReconciliacionData copyWithCompanion(SyncReconciliacionCompanion data) {
    return SyncReconciliacionData(
      id: data.id.present ? data.id.value : this.id,
      ultimaReconciliacion: data.ultimaReconciliacion.present
          ? data.ultimaReconciliacion.value
          : this.ultimaReconciliacion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncReconciliacionData(')
          ..write('id: $id, ')
          ..write('ultimaReconciliacion: $ultimaReconciliacion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, ultimaReconciliacion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncReconciliacionData &&
          other.id == this.id &&
          other.ultimaReconciliacion == this.ultimaReconciliacion);
}

class SyncReconciliacionCompanion
    extends UpdateCompanion<SyncReconciliacionData> {
  final Value<String> id;
  final Value<DateTime?> ultimaReconciliacion;
  final Value<int> rowid;
  const SyncReconciliacionCompanion({
    this.id = const Value.absent(),
    this.ultimaReconciliacion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncReconciliacionCompanion.insert({
    required String id,
    this.ultimaReconciliacion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<SyncReconciliacionData> custom({
    Expression<String>? id,
    Expression<DateTime>? ultimaReconciliacion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ultimaReconciliacion != null)
        'ultima_reconciliacion': ultimaReconciliacion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncReconciliacionCompanion copyWith(
      {Value<String>? id,
      Value<DateTime?>? ultimaReconciliacion,
      Value<int>? rowid}) {
    return SyncReconciliacionCompanion(
      id: id ?? this.id,
      ultimaReconciliacion: ultimaReconciliacion ?? this.ultimaReconciliacion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ultimaReconciliacion.present) {
      map['ultima_reconciliacion'] =
          Variable<DateTime>(ultimaReconciliacion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncReconciliacionCompanion(')
          ..write('id: $id, ')
          ..write('ultimaReconciliacion: $ultimaReconciliacion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV7 extends GeneratedDatabase {
  DatabaseAtV7(QueryExecutor e) : super(e);
  late final SyncPendientes syncPendientes = SyncPendientes(this);
  late final ItemsCache itemsCache = ItemsCache(this);
  late final UsuarioActivo usuarioActivo = UsuarioActivo(this);
  late final SyncReconciliacion syncReconciliacion = SyncReconciliacion(this);
  late final Index uxSyncIdempotency = Index('ux_sync_idempotency',
      'CREATE UNIQUE INDEX ux_sync_idempotency ON sync_pendientes (idempotency_key)');
  late final Index ixSyncEnvio = Index('ix_sync_envio',
      'CREATE INDEX ix_sync_envio ON sync_pendientes (estado, secuencia)');
  late final Index ixSyncEntidad = Index('ix_sync_entidad',
      'CREATE INDEX ix_sync_entidad ON sync_pendientes (tipo_entidad, entidad_id, secuencia)');
  late final Index ixSyncUsuario = Index('ix_sync_usuario',
      'CREATE INDEX ix_sync_usuario ON sync_pendientes (usuario_id, estado)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        syncPendientes,
        itemsCache,
        usuarioActivo,
        syncReconciliacion,
        uxSyncIdempotency,
        ixSyncEnvio,
        ixSyncEntidad,
        ixSyncUsuario
      ];
  @override
  int get schemaVersion => 7;
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
