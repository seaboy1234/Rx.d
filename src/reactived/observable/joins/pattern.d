module reactived.observable.joins.pattern;

import std.meta;

import reactived;

class Pattern(TSources...) if (allSatisfy!(isObservable, TSources))
{
    alias TElements = ElementTypes!TSources;

    TSources _values;

    alias _values this;

    package this(TSources values)
    {
        _values = values;
    }

    Pattern!(TSources, Observable!T) and(T)(Observable!T value)
    {
        return new Pattern!(TSources, Observable!T)(_values, value);
    }

    Plan!(TResult, TSources) then(TResult)(TResult delegate(TElements) selector)
    {
        return new Plan!(TResult, TSources)(this, selector);
    }
}

alias and = pattern;

auto pattern(TSources...)(TSources values) if (allSatisfy!(isObservable, TSources))
{
    return new Pattern!(TSources)(values);
}

unittest
{
    class A
    {
    }

    class B
    {
    }

    class C
    {
    }

    Pattern!(Observable!A, Observable!B) x;

    static assert(is(typeof(x[0]) == Observable!A));
    static assert(is(typeof(x[1]) == Observable!B));

    static assert(is(typeof(x.and((Observable!C)
            .init)) == Pattern!(Observable!A, Observable!B, Observable!C)));

    static assert(is(typeof({
                Pattern!(Observable!A, Observable!B) y = new Pattern!(Observable!A, Observable!B)((Observable!A)
                .init, (Observable!B).init);
            })));
    static assert(is(typeof(pattern((Observable!A).init, (Observable!B).init,
            (Observable!C).init)) == Pattern!(Observable!A, Observable!B, Observable!C)));
}
