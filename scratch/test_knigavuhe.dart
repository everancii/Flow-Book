import 'package:audiobookflow/resources/services/knigavuhe/knigavuhe_detail_service.dart';

void main() async {
  final service = KnigavuheDetailService();
  final result = await service.getAudiobookFiles('https://knigavuhe.org/book/legkijj-sposob-brosit-kurit/');
  result.fold(
    (error) => print('ERROR: $error'),
    (data) {
      print('SUCCESS: Found ${data.files.length} files');
      for (var i = 0; i < data.files.length; i++) {
        final f = data.files[i];
        print('File $i: title="${f.title}", url="${f.url}", duration=${f.length}');
      }
    },
  );
}
