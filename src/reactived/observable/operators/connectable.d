module reactived.observable.operators.connectable;

import std.functional;
import reactived.observable;
import reactived.observer;
import reactived.subject;
import reactived.disposable;
import disposable = reactived.disposable;

ConnectableObservable!T publish(T)(Observable!T observable)
{
    static class AnonymousConnectableObservable : ConnectableObservable!T
    {
        private Subject!T _subject;
        private Observable!T _observable;

        this(Observable!T observable)
        {
            _subject = new Subject!T();
            _observable = observable;
        }

        void connect()
        {
            _observable.subscribe(_subject);
        }

        Disposable subscribe(Observer!T observer)
        {
            return _subject.subscribe(observer);
        }
    }

    return new AnonymousConnectableObservable(observable);
}

unittest
{
    import std.random : Random, unpredictableSeed;
    import reactived.util : dump;
    import reactived.scheduler : observeOn, currentThreadScheduler;

    // dfmt off
    auto o = Random(unpredictableSeed).asObservable()
                                      .observeOn(currentThreadScheduler)
                                      .take(10)
                                      .publish();
    // dfmt on

    uint[] items = (uint[]).init;

    o.subscribe((x) { items ~= x; });

    o.subscribe((x) => assert(items[$ - 1] == x));

    o.dump("publish()");

    o.connect();

    currentThreadScheduler.work();
}
