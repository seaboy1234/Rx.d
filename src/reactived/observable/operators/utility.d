module reactived.observable.operators.utility;

import std.functional;
import std.traits;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import disposable = reactived.disposable;

/**
    Forwards calls on a subscriber to the given observer.
*/
Observable!T doOnEach(T)(Observable!T observable, Observer!T observer) pure @safe nothrow
{
    Disposable subscribe(Observer!T subscriber)
    {
        void onNextImpl(T value)
        {
            observer.onNext(value);
            subscriber.onNext(value);
        }

        void onCompletedImpl()
        {
            observer.onCompleted();
            subscriber.onCompleted();
        }

        void onErrorImpl(Throwable error)
        {
            observer.onError(error);
            subscriber.onError(error);
        }

        return observable.subscribe(&onNextImpl, &onCompletedImpl, &onErrorImpl);
    }

    return create(&subscribe);
}

/**
    Forwards calls on a subscriber to the given `onNext`, `onCompleted`, and `onError` handlers.
*/
Observable!T doOnEach(T)(Observable!T observable, void delegate(T) onNext,
        void delegate() onCompleted, void delegate(Throwable) onError) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        void onNextImpl(T value)
        {
            onNext(value);
            observer.onNext(value);
        }

        void onCompletedImpl()
        {
            onCompleted();
            observer.onCompleted();
        }

        void onErrorImpl(Throwable error)
        {
            onError(error);
            observer.onError(error);
        }

        return observable.subscribe(&onNextImpl, &onCompletedImpl, &onErrorImpl);
    }

    return create(&subscribe);
}

///
unittest
{
    import reactived.util : dump;

    int count;
    bool completed;
    bool threw;

    range(1, 10).doOnEach((int) { ++count; }, () { completed = true; }, (Throwable) {
        threw = true;
    }).dump("doOnEach()");

    assert(count == 10);
    assert(completed);
    assert(!threw);

    error!(int)(new Exception("Failed")).doOnError!int((Throwable) {
        threw = true;
    }).dump("error");

    assert(threw);
}

/**
    Forwards calls on a subscriber to the given `onNext` handler.
*/
Observable!T doOnNext(T)(Observable!T observable, void delegate(T) onNext) pure @safe nothrow
{
    return doOnEach(observable, onNext, delegate() {  }, delegate(Throwable) {  });
}

/**
    Forwards calls on a subscriber to the given `onCompleted` handler.
*/
Observable!T doOnCompleted(T)(Observable!T observable, void delegate() onCompleted) pure @safe nothrow
{
    return doOnEach(observable, delegate(T) {  }, onCompleted, delegate(Throwable) {
    });
}

/**
    Forwards calls on a subscriber to the given `onError` handler.
*/
Observable!T doOnError(T)(Observable!T observable, void delegate(Throwable) onError) pure @safe nothrow
{
    return doOnEach!T(observable, delegate(T) {  }, delegate() {  }, onError);
}

/**
    Forwards subscription events to the given `onSubscribe` and `onUnsubscribe` handlers.
*/
Observable!T doOnSubscription(T)(Observable!T observable,
        void delegate(Observer!T) onSubscribe, void delegate(Observer!T) onUnsubscribe) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        onSubscribe(observer);

        return new CompositeDisposable(createDisposable(() {
                onUnsubscribe(observer);
            }), observable.subscribe(observer));
    }

    return create(&subscribe);
}

///
unittest
{
    import reactived.util : dump;

    int subscribes;
    int unsubscribes;

    Observable!int o = single(1).doOnSubscription((Observer!int) { ++subscribes; }, (Observer!int) {
        ++unsubscribes;
    });

    Disposable sub1 = o.dump("doOnSubscription1");

    assert(subscribes == 1);
    assert(unsubscribes == 0);

    sub1.dispose();

    assert(unsubscribes == 1);

    Disposable sub2 = o.dump("doOnSubscription2");

    assert(subscribes == 2);
    assert(unsubscribes == 1);

    sub2.dispose();

    assert(subscribes == unsubscribes);
}

/**
    Forwards subscription events to the given `onSubscribe` handler.
*/
Observable!T doOnSubscribe(T)(Observable!T observable, void delegate(Observer!T) onSubscribe)
{
    return doOnSubscription(observable, onSubscribe, (Observer!T) {  });
}

/**
    Forwards unsubscription events to the given `onUnsubscribe` handler.
*/
Observable!T doOnUnsubscribe(T)(Observable!T observable, void delegate(Observer!T) onUnsubscribe)
{
    return doOnSubscription(observable, (Observer!T) {  }, onUnsubscribe);
}

Observable!(Notification!T) materialize(T)(Observable!T source) @safe pure nothrow
{
    Disposable subscribe(Observer!(Notification!T) observer)
    {
        void onNext(T value)
        {
            observer.onNext(new OnNextNotification!T(value));
        }

        void onCompleted()
        {
            observer.onNext(new OnCompletedNotification!T());
            observer.onCompleted();
        }

        void onError(Throwable error)
        {
            observer.onNext(new OnErrorNotification!T(error));
            observer.onError(error);
        }

        return source.subscribe(&onNext, &onCompleted, &onError);
    }

    return create(&subscribe);
}

Observable!T dematerialize(T)(Observable!(Notification!T) source)
{
    Disposable subscribe(Observer!T observer)
    {
        void onNext(Notification!T value)
        {
            switch (value.kind) with (NotificationKind)
            {
            case onNext:
                observer.onNext(value.value);
                break;
            case onCompleted:
                observer.onCompleted();
                break;
            case onError:
                observer.onError(value.error);
                break;
            default:
                assert(0);
            }
        }

        return source.subscribe(&onNext, {  }, (Throwable) {  });
    }

    return create(&subscribe);
}

unittest
{
    // dfmt off
    range(0, 10).materialize()
                .dematerialize()
                .sequenceEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
                .subscribe(x => assert(x));

    // dfmt on
}
