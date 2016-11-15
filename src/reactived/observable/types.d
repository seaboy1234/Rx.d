module reactived.observable.types;

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
                if (_completed)
                {
                    return;
                }

                try
                {
                    onNext_(value);
                }
                catch (Exception e)
                {
                    onError(e);
                }
            }

            void onCompleted()
            {
                if (_completed)
                {
                    return;
                }
                _completed = true;
                onCompleted_();
            }

            void onError(Throwable error)
            {
                if (_completed)
                {
                    return;
                }

                onError_(error);
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

/// Represents a value with no information.
struct Unit
{
}
