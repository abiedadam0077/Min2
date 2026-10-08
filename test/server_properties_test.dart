import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/data/minecraft/server_properties.dart';
import 'package:voxelops/domain/server_models.dart';

void main() {
  test('keeps comments, ordering and unknown keys when settings change', () {
    final file = ServerPropertiesFile.parse('#Custom header\nmotd=Old\ncustom-key=keep-me\n');
    file.applySettings(const ServerSettings(motd: 'New motd', maxPlayers: 5, pvp: false));
    final text = file.toText();
    expect(text.startsWith('#Custom header'), isTrue);
    expect(text, contains('custom-key=keep-me'));
    expect(text, contains('motd=New motd'));
    expect(text, contains('max-players=5'));
    expect(text, contains('pvp=false'));
  });

  test('reads settings back from a file', () {
    final file = ServerPropertiesFile.parse('max-players=42\ngamemode=creative\nonline-mode=false\n');
    final settings = file.toSettings();
    expect(settings.maxPlayers, 42);
    expect(settings.gamemode, 'creative');
    expect(settings.onlineMode, isFalse);
  });

  test('defaults keep the level name for the world folder', () {
    expect(ServerPropertiesFile.withDefaults().get('level-name'), 'world');
  });
}
