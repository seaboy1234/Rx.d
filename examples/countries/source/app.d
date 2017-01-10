import std.concurrency;
import std.datetime;
import std.json;
import std.net.curl;
import std.stdio;

import etc.c.curl : CurlOption;

import reactived;

void main()
{
    enum NAMES = "http://country.io/names.json";
    enum CONTINENTS = "http://country.io/continent.json";
    enum CAPITALS = "http://country.io/capital.json";

    writeln("----------COUNTRIES EXAMPLE----------");

    // dfmt off
    auto isoCodesAndNames = start!({ 
        auto x = get(NAMES);
        return x;
    }).replay()
      .refCount()
      .map!parseJSON()
      .flatMap!(x => getPairs(x).asObservable(defaultScheduler));

    auto names = isoCodesAndNames.map!(x => x.value);

    auto isoCodes = isoCodesAndNames.map!(x => x.key);

    auto continents = start!({ 
        auto x = get(CONTINENTS);
        return x;
    }).replay()
      .refCount()
      .map!parseJSON()
      .flatMap!(x => getPairs(x).asObservable(defaultScheduler))
      .map!(x => x.value);

    auto capitals = start!({ 
        auto x = get(CAPITALS);
        return x;
    }).replay()
      .refCount()
      .map!parseJSON()
      .flatMap!(x => getPairs(x).asObservable(defaultScheduler))
      .map!(x => x.value);

    struct CountryInfo
    {
        string iso, name, continent, capital;
    }

    CountryInfo countryInfo(string iso, string name, string continent, string capital)
    {
        return CountryInfo(iso, name, continent, capital);
    }

    auto countries = isoCodes.and(names, continents, capitals)
                             .then!(CountryInfo)(&countryInfo)
                             .when()
                             .groupBy!(x => x.continent);

    // dfmt on

    CompositeDisposable subscriptions = new CompositeDisposable();
    
    Disposable subscription = countries.subscribe((continent) {

        // Get the individual country reports.
        subscriptions ~= continent.subscribe((country) {
            writeln("ISO: ", country.iso);
            writeln("Name: ", country.name);
            writeln("Capital: ", country.capital);
            writeln("Continent: ", country.continent);
            writeln();
        });

        // Get the tally.
        subscriptions ~= continent.length.subscribe(x => writeln(continent.key, " has ", x, " countries."));

    }, (error) => writeln("Error: ", error));
    
    subscriptions ~= subscription;

    countries.wait();

    subscriptions.dispose();
}

Pair[] getPairs(JSONValue obj)
{
    Pair[] pairs;

    foreach(key, value; obj.object)
    {
        pairs ~= Pair(key, value.str);
    }

    return pairs;
}

struct Pair
{
    string key, value;
}
