# Rx.d
*Reactive Extensions for the D Programming Language* 
---
[![Build Status](https://travis-ci.org/seaboy1234/Rx.d.svg?branch=master)](https://travis-ci.org/seaboy1234/Rx.d) 
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

This is an attempt at implementing [ReactiveX](http://reactivex.io/) in the D Programming Language.
Rx.d allows the composition of powerful Observable sequences with familiar patterns.

The API is based largely on the Rx.NET API with some minor changes.  Efforts are made to maintain
compatibility with the ReactiveX spec.

```d
/* 
continents.json:
[
    ...
    { 
        "ISO": "US",
        "Name": "United States",
        "Continent" : "NA" 
    },
    { 
        "ISO": "UY",
        "Name": "Uruguay",
        "Continent": "SA" 
    },
    { 
        "ISO": "UZ",
        "Name": "Uzbekistan",
        "Continent": "AS" 
    },
    { 
        "ISO": "VA", 
        "Name": "Vatican City",
        "Continent": "EU" 
    },
    { 
        "ISO": "VC",
        "Name": "Saint Vincent and the Grenadines",
        "Continent": "NA" 
    },
    ...
]
*/

enum COUNTRIES = "path/to/continents.json";

struct Country
{
    string iso, name, continent;
}

auto continents = start!get(COUNTRIES)
                       .map!parseJSON()
                       .flatMap!(x => x.array.asObservable(defaultScheduler))
                       .map!(x => Country(x["ISO"].str, x["Name"].str, x["Continent"].str))
                       .groupBy(x => x.continent);

continents.subscribe((continent) {
    continent.length.subscribe(length => writeln(continent.key, " has ", length, " countries");
});

```

## Concepts

At the core of Rx.d is the Observable, Observer, and Disposable interfaces.

```d
// src/reactived/observable/types.d
interface Observable(T)
{
    alias ElementType = T;

    Disposable subscribe(Observer!(T) observer);
}

// src/reactived/observer.d
interface Observer(T)
{
    // Invoked when the next value in the Observable sequence is available.
    void onNext(T value);

    // Invoked when the Observable sequence terminates due to an error.
    void onError(Throwable error);

    // Invoked when the Observable sequence terminates successfully.
    void onCompleted();
}

// src/reactived/disposable.d
interface Disposable
{
    void dispose() @nogc;
}
```

Layered on top of these interfaces are a collection of operators for combining, 
filtering, transforming, and managing sequences of data. For example, the `map` 
operator takes `TInput`s to `TOutput`s:

```d
import reactived;

[1, 2, 3].asObservable().map!(x => x * 10).asRange() // [10, 20, 30]

import std.conv;

[1, 2, 3].asObservable().map!(x => to!string(x)).asRange() // ["1", "2", "3"]
```

More complex operators can combine several observable sequences into one:

```d
import reactived;
import std.conv;

auto questions = just("what is the answer to life?");
auto answers = just(42);

questions.and(answers)
         .then!string((q, a) => q ~ " " ~ to!string(a) ~ "!")
         .when()
         .endWith("Anything else?")
         .asRange(); // ["what is the answer to life? 42!", "Anything else?"]
```

`And/Then/When` can combine any number of Observables into one:

```d
range(0, 10).and(range(10, 10))
            .and(range(20, 10))
            .then!int((a, b, c) => a + b + c) // [0 + 10 + 20, 1 + 11 + 21, ...]
            .when()
            .wait(); // returns the last element from the sequence: 57 (9 + 19 + 29)
```

Turn a long-running operation into a cancelable, asynchronous Observable:

```d
import std.stdio;

Disposable subscription = start!longWebRequest("http://example.org/").subscribe(x => writeln(x), 
                                                                               () => writeln("Completed"), 
                                                                          (error) => writeln("An error ocurred: ", error));

// subscription.dispose(); // cancel the action.
```
