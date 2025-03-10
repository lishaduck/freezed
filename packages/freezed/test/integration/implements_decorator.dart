import 'package:freezed_annotation/freezed_annotation.dart';

part 'implements_decorator.freezed.dart';

@freezed
abstract class SimpleImplements with _$SimpleImplements {
  const factory SimpleImplements.person(String name, int age) = SimplePerson;

  @With<AdministrativeArea<House>>()
  const factory SimpleImplements.street(String name) = SimpleStreet;

  @With<House>()
  const factory SimpleImplements.city(String name, int population) = SimpleCity;

  @With<House>()
  @Implements<GeographicArea>()
  const factory SimpleImplements.country(String name, int population) =
      SimpleCountry;
}

@freezed
abstract class CustomMethodImplements with _$CustomMethodImplements {
  const CustomMethodImplements._();

  const factory CustomMethodImplements.person(String name, int age) =
      PersonCustomMethod;

  @With<Shop>()
  @With<AdministrativeArea<House>>()
  const factory CustomMethodImplements.street(String name) = StreetCustomMethod;

  @With<House>()
  @Implements<Named>()
  @Implements<GeographicArea>()
  const factory CustomMethodImplements.city(String name, int population) =
      CityCustomMethod;

  void function() {}
}

@freezed
abstract class GenericImplements<T> with _$GenericImplements<T> {
  const factory GenericImplements.person(String name, int age) =
      GenericPerson<T>;

  @With.fromString('AdministrativeArea<T>')
  @Implements.fromString('Generic<T>')
  const factory GenericImplements.street(String name, T value) =
      GenericStreet<T>;

  @With<House>()
  @Implements<GeographicArea>()
  const factory GenericImplements.city(String name, int population) =
      GenericCity<T>;
}

abstract class Generic<T> {
  T get value;
}

abstract class GeographicArea {
  String get name;
}

abstract class Named {
  String get name;
}

mixin AdministrativeArea<T> {
  T method(T value) => value;
}

mixin class House {}

mixin class Shop {}
