module reactived.subject;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import reactived.util;
import std.exception : enforce;
import std.algorithm;

/// Represents a hybrid between an Observable and Observer, providing the functions of both.  
/// This will often be the root on an Observable sequence.
class Subject(T) : ObserverBase!T, Observable!T
{
    private
    {
        bool _completed;
        Observer!(T)[] _observers;
    }

    /// Provides the next value to the underlying Observers.
    override void onNextCore(T value)
    {
        foreach (observer; _observers[])
        {
            observer.onNext(value);
        }
    }

    /// Causes the sequence to complete. 
    override void onCompletedCore()
    {
        foreach (observer; _observers[])
        {
            observer.onCompleted();
        }
        _completed = true;
    }

    /// Causes the sequence to complete with the specified error.
    override void onErrorCore(Throwable error)
    {
        _completed = true;

        foreach (observer; _observers[])
        {
            observer.onError(error);
        }
    }

    /// Subscribes an Observer to this Observable sequence.
    Disposable subscribe(Observer!(T) observer)
    {
        import std.algorithm : countUntil, remove;

        if (_completed)
        {
            observer.onCompleted();
            return empty();
        }

        _observers ~= observer;

        return createDisposable(() @nogc{
            if (_completed)
            {
                return;
            }
            synchronized
            {
                size_t index = indexOf(observer);
                assert(index != -1);

                _observers = _observers.remove(index);
                assert(indexOf(observer) == -1);
            }
        });
    }

    private size_t indexOf(Observer!T observer) pure @safe @nogc
    {
        foreach (i, value; _observers)
        {
            if (value is observer)
            {
                return i;
            }
        }

        return -1;
    }
}

///
unittest
{
    import std.stdio : writeln;

    int global;

    class MyObserver : Observer!(int)
    {
        void onNext(int value)
        {
            assert(value < 3);
            global++;
            writeln(value);
        }

        void onCompleted()
        {
            writeln("Completed");
        }

        void onError(Throwable error)
        {
            writeln(error.msg);
        }
    }

    auto subject = new Subject!int();
    auto observer1 = new MyObserver();
    auto observer2 = new MyObserver();

    auto token1 = subject.subscribe(observer1);
    auto token2 = subject.subscribe(observer2);

    subject.onNext(1); // => 1 [global == 2]
    subject.onNext(2); // => 2 [global == 4]
    token1.dispose();
    token2.dispose();
    subject.onNext(3); // (nothing)

    assert(global == 4);
}

/// Represents a Subject which is able to replay the values it receives.
class ReplaySubject(T) : Subject!(T)
{
    import std.datetime : Clock, SysTime, Duration;

    private
    {
        Duration _window;
        SubjectItem[] _items;
    }

    private struct SubjectItem
    {
        SysTime time;
        void delegate(Observer!T) dg;
    }

    /// Instantiates the ReplaySubject with the max Duration.
    this()
    {
        this(Duration.max);
    }

    /// Instantiates the ReplaySubject with the specified window.
    this(Duration window)
    {
        _window = window;
    }

    override void onNextCore(T value)
    {
        _items ~= SubjectItem(Clock.currTime(), (observer) {
            observer.onNext(value);
        });
        super.onNextCore(value);
    }

    override void onErrorCore(Throwable error)
    {
        _items ~= SubjectItem(Clock.currTime(), (observer) {
            observer.onError(error);
        });
        super.onErrorCore(error);
    }

    override void onCompletedCore()
    {
        _items ~= SubjectItem(Clock.currTime(), (observer) {
            observer.onCompleted();
        });
        super.onCompletedCore();
    }

    override Disposable subscribe(Observer!T observer)
    {
        import std.algorithm : filter = filter, countUntil, remove;

        try
        {
            auto range = _items.filter!(g => g.time - Clock.currTime() <= _window);
            foreach (item; range)
            {
                item.dg(observer);
            }

            foreach (item; range)
            {
                size_t index = _items.countUntil(item);
                assert(index != -1);
                _items.remove(index);
            }
        }
        catch (Exception e)
        {
            onError(e);
        }
        auto disposable = super.subscribe(observer);
        return disposable;
    }
}

///
unittest
{
    import std.stdio : writeln;

    class MyObserver : Observer!(int)
    {
        void onNext(int value)
        {
            writeln(value);
        }

        void onCompleted()
        {
            writeln("Completed");
        }

        void onError(Throwable error)
        {
            writeln(error.msg);
        }
    }

    auto subject = new ReplaySubject!int();
    auto observer = new MyObserver();

    subject.onNext(1);
    auto token = subject.subscribe(observer); // => 1
    subject.onNext(2); // => 2
    token.dispose();
    subject.onNext(3);

    subject.subscribe(observer); // => 1
    // => 2
    // => 3
    subject.onCompleted(); // => Completed
}

/// Masks the underlying source Observable.
Observable!T asObservable(T)(Observable!T source)
{
    Disposable subscribe(Observer!T observer)
    {
        return source.subscribe(observer);
    }

    return create(&subscribe);
}

/// 
unittest
{
    Subject!int subject = new Subject!int();

    auto masked = subject.asObservable();

    assert(!is(masked : Subject!int));
}
