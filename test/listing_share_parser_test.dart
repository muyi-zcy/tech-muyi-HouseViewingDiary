import 'package:flutter_test/flutter_test.dart';
import 'package:house_viewing_diary_flutter/listing_share_parser.dart';

void main() {
  test('安居客竖线格式与紧挨 URL', () {
    const text =
        '高速东方御府 | 53万 | 3室2厅 99.61平米 | 鸠江 万春购物广场https://m.anjuke.com/wuh/sale/A7387836171/?isauction=0&from=a-ajk&pm=copylink【安居客】';
    final f = parseAnjukePipeLine(text);
    expect(f, isNotNull);
    expect(f!.community, '高速东方御府');
    expect(f.price, '53万');
    expect(f.area, '99.61');
    expect(f.bedrooms, 3);
    expect(f.livingRooms, 2);
    expect(f.sourceUrl, contains('anjuke.com'));
    expect(f.locationHint, contains('鸠江'));
  });

  test('贝壳逗号格式与千分位单价', () {
    const text =
        '融创金地童话森林,3室2厅,89.84平米,7,347元/平,66万,低楼层/24层,南 北，详情：https://m.ke.com/wuhu/ershoufang/103131274690.html?shareSource=beike_app。来自【贝壳APP】';
    final f = parseBeikeShareLine(text);
    expect(f, isNotNull);
    expect(f!.community, '融创金地童话森林');
    expect(f.area, '89.84');
    expect(f.totalFloors, 24);
    expect(f.price, '66万');
    expect(f.sourceUrl, contains('ke.com'));
    expect(f.unitPriceYuanPerSqm, contains('7347'));
  });
}
