import 'package:flutter_bloc/flutter_bloc.dart';

import 'keyboard_state.dart';

class KeyboardCubit extends Cubit<KeyboardState> {
  KeyboardCubit() : super(const KeyboardState());

  void toggleModifier(KeyModifier modifier) {
    final held = Set<KeyModifier>.of(state.heldModifiers);
    if (!held.remove(modifier)) {
      held.add(modifier);
    }
    emit(state.copyWith(heldModifiers: held));
  }

  void releaseAll() {
    if (state.heldModifiers.isEmpty) return;
    emit(state.copyWith(heldModifiers: const {}));
  }
}
