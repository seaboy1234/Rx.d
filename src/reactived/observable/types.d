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
        class AnonymousObserver : Observer!T
        {
            private bool _completed;
            void onNext(T value)
            {
                try
                {
                    synchronized (this)
                    {
                        if (_completed)
                        {
                            return;
                        }
                        onNext_(value);
                    }
                }
                catch (Exception e)
                {
                    onError(e);
                }
            }

            void onCompleted()
            {
                synchronized (this)
                {
                    if (_completed)
                    {
                        return;
                    }
                    _completed = true;
                    onCompleted_();
                }
            }

            void onError(Throwable error)
            {
                synchronized (this)
                {
                    if (_completed)
                    {
                        return;
                    }

                    onError_(error);
                }
            }
        }

        return subscribe(new AnonymousObserver());
    }

    /// Subscribe to an Observable using an onNext method and empty stubs for onCompleted and onError.
    final Disposable subscribe(void delegate(T) onNext)
    {
        void onCompleted()
        {

        }

        void onError(Throwable)
        {

        }

        return subscribe(onNext, &onCompleted, &onError);
    }

    /// Subscribe to an Observable using onNext and onCompleted methods, leaving onError empty.
    final Disposable subscribe(void delegate(T) onNext, void delegate() onCompleted)
    {
        void onError(Throwable)
        {

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
Observable!E asObservable(T, E)(T observable) if (isObservable!(T, E))
{
    import reactived.observable.generators : create;

    Disposable subscribe(Observer!E observer)
    {
        return observable.subscribe(observer);
    }

    return create(&subscribe);
}

template isObservable(T, E)
{
    enum bool isObservable = __traits(compiles, {
            T observable = T.init;
            Observer!E observer = void;

            Disposable x = observable.subscribe(observer);
        });
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

    assert(isObservable!(Observable!(int), int));
    assert(!isObservable!(B, int), "B is not observable");
    assert(isObservable!(A, int), "A is observable");
}

Observable!(E) synchronize(O, E = O.ElementType)(O observable)
        if (isObservable!(O, E))
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
