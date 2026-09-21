import 'package:flutter_bloc/flutter_bloc.dart';

import 'presenter_state.dart';

class PresenterCubit extends Cubit<PresenterState> {
  PresenterCubit() : super(const PresenterState());

  void toggleBlackScreen() {
    emit(state.copyWith(screenBlanked: !state.screenBlanked));
  }
}
