import 'package:flutter_test/flutter_test.dart';
import 'package:pas_de_tir_poc/pas_de_tir/screens/pas_de_tir_modals.dart';

void main() {
  test('titre du résultat selon le score', () {
    expect(resultTitle(5, 5), 'Sans faute !');
    expect(resultTitle(4, 5), 'Belle série !');
    expect(resultTitle(3, 5), 'Belle série !');
    expect(resultTitle(2, 5), 'Bien essayé !');
    expect(resultTitle(0, 5), 'Pas cette fois !');
  });
}
