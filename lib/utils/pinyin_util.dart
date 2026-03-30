import 'package:pinyin/pinyin.dart';

String nameToPinyin(String name) {
  if (name.isEmpty) return '';
  try {
    return PinyinHelper.getPinyin(name, separator: ' ', format: PinyinFormat.WITHOUT_TONE);
  } catch (_) {
    return '';
  }
}
