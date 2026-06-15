part of 'knigavuhe_lists_bloc.dart';

@immutable
sealed class KnigavuheListsEvent {}

class FetchKnigavuheLists extends KnigavuheListsEvent {
  final String period;
  FetchKnigavuheLists({this.period = 'alltime'});
}
