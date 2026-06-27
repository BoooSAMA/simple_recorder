// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecordingTaskAdapter extends TypeAdapter<RecordingTask> {
  @override
  final int typeId = 3;

  @override
  RecordingTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecordingTask(
      id: fields[0] as String,
      roomId: fields[1] as String,
      siteId: fields[2] as String,
      userName: fields[3] as String,
      face: fields[4] as String,
      title: fields[5] as String,
      addTime: fields[6] as DateTime,
      outputPath: fields[7] as String,
      duration: fields[8] as String,
      fileSize: fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RecordingTask obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roomId)
      ..writeByte(2)
      ..write(obj.siteId)
      ..writeByte(3)
      ..write(obj.userName)
      ..writeByte(4)
      ..write(obj.face)
      ..writeByte(5)
      ..write(obj.title)
      ..writeByte(6)
      ..write(obj.addTime)
      ..writeByte(7)
      ..write(obj.outputPath)
      ..writeByte(8)
      ..write(obj.duration)
      ..writeByte(9)
      ..write(obj.fileSize);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
