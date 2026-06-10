class PredictionModel {
  String? placeId;
  String? mainText;
  String? secondaryText;

  PredictionModel({
    this.placeId,
    this.mainText,
    this.secondaryText,
  });

  // Named constructor to create PredictionModel from JSON
  static PredictionModel fromJson(Map<String, dynamic> json) {
    return PredictionModel(
      placeId: json['place_id'],
      mainText: json['structured_formatting']?['main_text'],
      secondaryText: json['structured_formatting']?['secondary_text'],
    );
  }
}

