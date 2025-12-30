import 'package:running_historian/domain/landmark.dart';

const List<Landmark> kLandmarks = [
  Landmark(
    id: "1",
    name: "Ростовский кремль",
    lat: 47.2313,
    lon: 39.7233,
    radius: 500,
    fact: "Ростовский кремль был построен в 1589 году как укрепление против крымских татар.",
  ),
  Landmark(
    id: "2",
    name: "Мост через Дон",
    lat: 47.2200,
    lon: 39.7000,
    radius: 500,
    fact: "Этот мост был первым постоянным мостом через Дон, построенным в 1898 году.",
  ),
];

const List<String> kGeneralFacts = [
  "Ростов-на-Дону основан в 1749 году как военное укрепление.",
  "Население города составляет более 1 миллиона человек.",
];

const int kFactsIntervalMinutes = 2;
const int kMinIntervalBetweenFacts = 1;