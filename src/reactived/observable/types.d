module reactived.observable.types;

import std.datetime;

import reactived.observer;
import reactived.disposable : Disposable, createDisposable;
import std.range;

/// Represents an observable sequence of values.
interface Observable(T)
{
    alias ElementType = T;

    /// Subscribe to the Observable using an Observer.
    Disposable subscribe(Observer!(T) observer);

    /// Subscribe to the Observable using onNext, onCompleted, and onError methods.
    final Disposable subscribe(void delegate(T value) onNext_,
            void delegate() onCompleted_, void delegate(Throwable) onError_)
    {
        static class AnonymousObserver(T) : ObserverBase!T
        {
            private void delegate(T) _onNext;
            private void delegate() _onCompleted;
            private void delegate(Throwable) _onError;

            this(void delegate(T) onNext, void delegate() onCompleted,
                    void delegate(Throwable) onError)
            {
                _onNext = onNext;
                _onCompleted = onCompleted;
                _onError = onError;
            }

        protected:
            override void onNextCore(T value)
            {
                _onNext(value);
            }

            override void onCompletedCore()
            {
                _onCompleted();
            }

            override void onErrorCore(Throwable error)
            {
                _onError(error);
            }
        }

        return subscribe(new AnonymousObserver!T(onNext_, onCompleted_, onError_));
    }

    /// Subscribe to an Observable using an onNext method and empty stubs for onCompleted and onError.
    final Disposable subscribe(void delegate(T) onNext)
    {
        void onCompleted()
        {

        }

        void onError(Throwable e)
        {
            throw e;
        }

        return subscribe(onNext, &onCompleted, &onError);
    }

    /// Subscribe to an Observable using onNext and onCompleted methods, leaving onError empty.
    final Disposable subscribe(void delegate(T) onNext, void delegate() onCompleted)
    {
        void onError(Throwable e)
        {
            throw e;
        }

        return subscribe(onNext, onCompleted, &onError);
    }

    /// Subscribe to an Observable using onNext and onError methods, leaving onCompleted empty.
    final Disposable subscribe(void delegate(T) onNext, void delegate(Throwable) onError)
    {
        void onCompleted()
        {

        }

        return subscribe(onNext, &onCompleted, onError);
    }
}

interface GroupedObservable(TKey, TValue) : Observable!TValue
{
    TKey key() @property;
}

interface ConnectableObservable(T) : Observable!T
{
    void connect();
    void disconnect();

    bool connected() const @property;
}

abstract package(reactived) class ObserverBase(T) : Observer!T
{
    private bool _completed;

protected:
    abstract void onNextCore(T value);
    abstract void onCompletedCore();
    abstract void onErrorCore(Throwable error);

public:
    final void onNext(T value)
    {
        try
        {
            synchronized (this)
            {
                if (_completed)
                {
                    return;
                }
                onNextCore(value);
            }
        }
        catch (Exception e)
        {
            onError(e);
        }
    }

    final void onCompleted()
    {
        synchronized (this)
        {
            if (_completed)
            {
                return;
            }
            _completed = true;
            onCompletedCore();
        }
    }

    final void onError(Throwable error)
    {
        synchronized (this)
        {
            if (_completed)
            {
                return;
            }

            _completed = true;
            onErrorCore(error);
        }
    }
}

Disposable subscribe(T, O)(Observable!T observable, O observer)
        if (isObserver!(O, T))
{
    return observable.subscribe(&observer.onNext, &observer.onCompleted, &observer.onError);
}

unittest
{
    import reactived.observable : range;

    struct A
    {
        int count;

        void onNext(int value)
        {
            count++;
        }

        void onCompleted()
        {
            assert(count == 10);
        }

        void onError(Throwable)
        {
            assert(0);
        }
    }

    A a = A();

    Disposable x = subscribe!(int, A)(range(0, 10), a);
}

/// Converts 
Observable!E asObservable(T, E)(T observable) if (isObservableOfElement!(T, E))
{
    import reactived.observable.generators : create;

    Disposable subscribe(Observer!E observer)
    {
        return observable.subscribe(observer);
    }

    return create(&subscribe);
}

template isObservableOfElement(T, E)
{
    enum bool isObservableOfElement = is(typeof({
                T observable = T.init;
                Observer!E observer = void;

                Disposable x = observable.subscribe(observer);
            }));
}

template isObservable(T)
{
    enum bool isObservable = is(typeof({
                T observable = T.init;
                alias E = ElementType!T;

                return isObservableOfElement!(T, E);
            }));
}

unittest
{
    class A
    {
        Disposable subscribe(O)(O observer) if (isObserver!(O, int))
        {
            import reactived.disposable : empty;

            observer.onNext(1);

            return empty();
        }
    }

    struct B
    {
        void subscribe(Observer!int observer)
        {
        }
    }

    assert(isObservableOfElement!(Observable!(int), int));
    assert(!isObservableOfElement!(B, int), "B is not observable");
    assert(isObservableOfElement!(A, int), "A is observable");
}

Observable!(E) synchronize(O, E = O.ElementType)(O observable)
        if (isObservableOfElement!(O, E))
{
    import reactived : create;

    Disposable subscribe(Observer!(E) observer)
    {
        return asObservable!(O, E)(observable).subscribe(&observer.onNext,
                &observer.onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    bool completed;

    struct JankyObservable
    {
        alias ElementType = int;

        Disposable subscribe(Observer!int observer)
        {
            import reactived : taskScheduler;

            taskScheduler.run(() { observer.onNext(1); });
            taskScheduler.run(() { observer.onNext(2); });
            taskScheduler.run(() { observer.onNext(3); });
            taskScheduler.run(() { observer.onCompleted(); });

            return createDisposable({  });
        }
    }

    class UnsuspectingObserver : Observer!int
    {
        bool callingMethod;

        void callMethod()
        {
            import core.thread : Thread;
            import std.datetime : dur;

            assert(!callingMethod);
            assert(!completed);
            callingMethod = true;
            Thread.sleep(dur!"msecs"(100));
            callingMethod = false;
        }

        void onNext(int)
        {
            callMethod();
        }

        void onCompleted()
        {
            callMethod();
            completed = true;
        }

        void onError(Throwable)
        {
            callMethod();
        }
    }

    JankyObservable().synchronize().subscribe(new UnsuspectingObserver());
    while (!completed)
    {
    }
}

/// Represents a value with no information.
struct Unit
{
}

interface Notification(T)
{
@safe pure @property:
    NotificationKind kind();

    T value();
    bool hasValue();
    Throwable error();
}

package class OnNextNotification(T) : Notification!T
{
    private @safe
    {
        T _value;
    }

    this(T value) @safe pure @nogc
    {
        _value = value;
    }

@safe pure @nogc @property:
    NotificationKind kind()
    {
        return NotificationKind.onNext;
    }

    T value()
    {
        return _value;
    }

    bool hasValue()
    {
        return true;
    }

    Throwable error()
    {
        return null;
    }
}

package class OnErrorNotification(T) : Notification!T
{
    private @safe
    {
        Throwable _error;
    }

    this(Throwable error) @safe pure @nogc
    {
        _error = error;
    }

@safe pure @nogc @property:
    NotificationKind kind()
    {
        return NotificationKind.onError;
    }

    T value()
    {
        return T.init;
    }

    bool hasValue()
    {
        return false;
    }

    Throwable error()
    {
        return _error;
    }
}

package class OnCompletedNotification(T) : Notification!T
{
@safe pure @nogc @property:
    NotificationKind kind()
    {
        return NotificationKind.onCompleted;
    }

    T value()
    {
        return T.init;
    }

    bool hasValue()
    {
        return false;
    }

    Throwable error()
    {
        return null;
    }
}

enum NotificationKind
{
    onNext,
    onCompleted,
    onError
}

struct Timestamp(T)
{
    SysTime timestamp;
    T value;
}

struct TimeInterval(T)
{
    Duration duration;
    T value;
}
