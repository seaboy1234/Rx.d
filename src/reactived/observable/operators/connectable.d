module reactived.observable.operators.connectable;

import std.functional;
import reactived.observable;
import reactived.observer;
import reactived.subject;
import reactived.disposable;
import disposable = reactived.disposable;

private template publishSubject(TSubject)
{
    ConnectableObservable!T publishSubject(T)(Observable!T observable)
    {
        static class AnonymousConnectableObservable : ConnectableObservable!T
        {
            private TSubject _subject;
            private Observable!T _observable;
            private AssignmentDisposable!Disposable _subscription;
            private bool _connected;

            this(Observable!T observable) pure @safe nothrow
            {
                _subject = new TSubject();
                _observable = observable;
                _subscription = assignmentDisposable();
            }

            void connect()
            {
                if (!_connected)
                {
                    _connected = true;
                    _subscription = _observable.subscribe(_subject);
                }
            }

            bool connected() const @safe @property
            {
                return _connected;
            }

            Disposable subscribe(Observer!T observer)
            {
                return _subject.subscribe(observer);
            }

            void disconnect() @nogc @trusted
            {
                if (_connected)
                {
                    _connected = false;
                    _subscription.disposable.dispose();
                }
            }
        }

        return new AnonymousConnectableObservable(observable);
    }
}

ConnectableObservable!T publish(T)(Observable!T observable) pure @safe nothrow
{
    return publishSubject!(Subject!T)(observable);
}

unittest
{
    import std.random : Random, unpredictableSeed;
    import reactived.util : dump;
    import reactived.scheduler : observeOn, currentThreadScheduler;

    // dfmt off
    auto o = Random(unpredictableSeed).asObservable()
                                      .take(10)
                                      .publish();
    // dfmt on

    uint[] items;

    auto d1 = o.subscribe((x) { items ~= x; });

    auto d2 = o.dump("publish");


    int index;
    auto d3 = o.subscribe((x) => assert(items[index++] == x));

    o.connect();
    o.wait();

    foreach (value; items)
    {
        import std.stdio : writeln;

        writeln("publish_items => ", value);
    }

    assert(items.length == 10);

    d1.dispose();
    d2.dispose();
    d3.dispose();
}

ConnectableObservable!T replay(T)(Observable!T source) pure @safe nothrow
{
    return publishSubject!(ReplaySubject!T)(source);
}

unittest
{
    import std.random : Random, unpredictableSeed;
    import reactived.util : dump;
    import reactived.scheduler : observeOn, currentThreadScheduler;

    // dfmt off
    auto o = Random(unpredictableSeed).asObservable()
                                      .take(10)
                                      .replay();
    // dfmt on

    uint[] items;

    auto d1 = o.subscribe((x) { items ~= x; });

    auto d2 = o.dump("replay");

    o.connect();

    int index;
    auto d3 = o.subscribe((x) => assert(items[index++] == x));

    o.wait();

    foreach (value; items)
    {
        import std.stdio : writeln;

        writeln("replay_items => ", value);
    }

    assert(items.length == 10);

    d1.dispose();
    d2.dispose();
    d3.dispose();
}

Observable!T refCount(T)(ConnectableObservable!T source) pure @safe nothrow
{
    static class RefCountedObservable : Observable!T
    {
        private RefCountDisposable _references;
        private ConnectableObservable!T _source;

        this(ConnectableObservable!T source) pure
        {
            _source = source;
            _references = new RefCountDisposable(() @trusted{
                source.disconnect();
            });
        }

        Disposable subscribe(Observer!T observer)
        {
            Disposable counted = _references.addReference(() {
                if (_references.canDispose)
                {
                    _references.dispose();
                }
            });
            Disposable subscription = _source.subscribe(observer);

            if (!_source.connected)
            {
                _source.connect();
            }

            return new CompositeDisposable(counted, subscription);
        }
    }

    return new RefCountedObservable(source);
}

unittest
{
    import std.random : Random, unpredictableSeed;
    import reactived.util : transparentDump;
    import reactived.scheduler : observeOn, currentThreadScheduler;

    int subscriptions;

    // dfmt off
    auto o = range(0, 10).doOnSubscription((Observer!int) {subscriptions++;}, (Observer!int){subscriptions--;})
                         .transparentDump("refCount")
                         .publish()
                         .refCount();
    // dfmt on

    int[] items = (int[]).init;

    auto d1 = o.subscribe((x) { items ~= x; });

    int index;
    auto d2 = o.subscribe((x) => assert(items[index++] == x));

    assert(items.length == 10);

    assert(subscriptions == 1);

    d1.dispose();
    d2.dispose();

    assert(subscriptions == 0);
}
