module reactived.observable.types;

import std.datetime;
import std.traits;

import reactived;
import reactived.disposable : emptyDisposable = empty;
import std.range;

alias RangeElementType = ElementType;

/**
    Represents an observable sequence of values.

    Authors:
        Christian Wilson, myself@christianwilson.me
*/
interface Observable(T)
{
    alias ElementType = T;

    /// Subscribe to the Observable using an Observer.
    Disposable subscribe(Observer!(T) observer);

    /**
        Subscribe to this $(D Observable!T) using $(D onNext), 
        $(D onCompleted), and $(D onError) handlers.

        This method will create an anonymous $(D Observer!T) from 
        the provided delegates.  If $(D onCompleted) or $(D onError)
        are not supplied, the default behavior will be implemented.
        For $(D onCompleted), this is simply to do nothing.  For
        $(D onError), on the other hand, the default behavior is
        to rethrow the $(D Exception) on the $(D Scheduler) on which 
        the call was made. $(RED $(BOLD This *MAY* cause the current
        thread to crash))!

        Authors:
            Christian Wilson, myself@christianwilson.me

        Params:
            onNext      = A `delegate` method which will be called whenever 
                          new values are posted.

            onCompleted = A `delegate` method which will be called when
                          the observable sequence ends without error.

            onError     = A `delegate` method which will be called when
                          the Observable sequence ends with an error.
                          While this method accepts any $(D Throwable),
                          only standard $(D Exception) objects are caught.

        Returns:
            A $(D Disposable) which unsubscribes the generated $(D Observer!T)
            from this $(D Observable!T).

        
    */
    final Disposable subscribe(void delegate(T value) onNext,
            void delegate() onCompleted, void delegate(Throwable) onError)
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

        return subscribe(new AnonymousObserver!T(onNext, onCompleted, onError));
    }

    /// ditto
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

    /// ditto
    final Disposable subscribe(void delegate(T) onNext, void delegate() onCompleted)
    {
        void onError(Throwable e)
        {
            throw e;
        }

        return subscribe(onNext, onCompleted, &onError);
    }

    /// ditto
    final Disposable subscribe(void delegate(T) onNext, void delegate(Throwable) onError)
    {
        void onCompleted()
        {

        }

        return subscribe(onNext, &onCompleted, onError);
    }

    final Observable!T opIndex(size_t index)
    {
        return this.elementAt(index);
    }

    final Observable!bool opEquals(Range)(Range b)
            if (isInputRange!Range && is(T : typeof(b.front)))
    {
        return sequenceEqual(this, b);
    }

    final auto opBinary(string op, TRight)(TRight rhs)
            if (!isInputRange!TRight && !isObservable!TRight)
    {
        static if (op == "~")
        {
            static if (is(T : TRight))
            {
                return endWith(this, rhs);
            }
        }
        else
        {
            // dfmt off
            enum string msg = "Operator " 
                            ~ op 
                            ~ " is not defined for "
                            ~ fullyQualifiedName!TRight 
                            ~ " and Observable!" 
                            ~ fullyQualifiedName!T;
            // dfmt on
            static assert(0, msg);
        }
    }

    final auto opBinaryRight(string op, TLeft)(TLeft lhs)
            if (isInputRange!TLeft && op == "~")
    {
        static if (is(T : RangeElementType!TLeft))
        {
            return startWith(this, lhs);
        }
    }

    final auto opBinary(string op, TRight)(TRight rhs) if (isInputRange!TRight)
    {
        static if (is(T : RangeElementType!TRight))
        {
            return concat(this, asObservable!TRight(rhs));
        }
    }

    final auto opBinary(string op, TRight)(TRight rhs) if (isObservable!TRight)
    {
        alias Right = TRight.ElementType;

        static if (op == "~")
        {
            return concat(this, cast(Observable!T) rhs);
        }
        else static if (op == "&")
        {
            return this.zip!((left, right) => Union!(T, Right)(left, right))(rhs);
        }
        else static if (op == "|" && is(T : Right))
        {
            return just(this).endWith(rhs).merge();
        }
        else
        {
            // dfmt off
            enum string msg = "Operator " 
                            ~ op 
                            ~ " is not defined for "
                            ~ fullyQualifiedName!TRight 
                            ~ " and Observable!" 
                            ~ fullyQualifiedName!T;
            // dfmt on
            static assert(0, msg);
        }
    }
}

unittest
{
    import reactived.util : assertEqual, dump;
    import std.conv : to;

    assertEqual(range(0, 5) ~ range(5, 5), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    //assertEqual(range(0, 5) ~ [5, 6, 7, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    assertEqual(range(0, 5) ~ 5, [0, 1, 2, 3, 4, 5]);

    Subject!string s1 = new ReplaySubject!string();
    Subject!int s2 = new ReplaySubject!int();

    auto o1 = s1 & s2;
    auto o2 = s1 | (s2.map!(x => to!string(x))());
    auto arr = [Union!(string, int)("Hello", 42), Union!(string, int)("World", 13)];

    auto equalsOp = (o1 == arr);

    s1.onNext("Hello");
    s1.onNext("World");

    s2.onNext(42);
    s2.onNext(13);

    s1.onCompleted();
    s2.onCompleted();

    o1.dump("s1 & s2");
    

    //assert(o1.sequenceEquals(equalsOp).wait());
}

/**
    Represents an $(D Observable) which has been grouped based 
    on a specific commonality, the key, of the values from
    the source $(D Observable).

    This interface plays a central role in the $(D groupBy)
    operator

    Params:
        TKey   = The key type to group on.
        TValue = The type of value this Observable emits.
    
    Authors:
        Christian Wilson, myself@christianwilson.me
*/
interface GroupedObservable(TKey, TValue) : Observable!TValue
{
    /**
        Gets the property which represents the value
        this $(D GroupedObservable) was created with.

        Returns:
            The value returned from the grouping function
    */
    TKey key() const @property;
}

/**
    Represents an $(D Observable) which does not start emitting 
    values until its $(D connect) method has been called.

    Authors:
        Christian Wilson, myself@christianwilson.me
*/
interface ConnectableObservable(T) : Observable!T
{
    /**
        Instructs this $(D ConnectableObservable) to subscribe to
        the underlying $(D Observable) and begin emitting values
    */
    void connect();

    /**
        Instructs this $(D ConnectableObservable) to unsubscribe from
        the underlying $(D Observable).
    */
    void disconnect() @nogc;

    /**
        Gets whether this $(D ConnectableObservable)'s `connect` method 
        has been called and is currently active.
    */
    bool connected() const @property;
}

abstract package(reactived) class ObservableBase(T) : Observable!T
{
    Disposable subscribe(Observer!T observer)
    {
        try
        {
            return subscribeCore(observer);
        }
        catch (Exception e)
        {
            observer.onError(e);
            return emptyDisposable();
        }
    }

    protected abstract Disposable subscribeCore(Observer!T observer);
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

/**
    Gets whether T is an $(D Observable).

    Any given T is considered an $(D Observable) if it implements
    the following interface:
    ---
    alias ElementType = TElement;
    Disposable subscribe(Observer!TElement);
    ---

    Authors:
        Christian Wilson, myself@christianwilson.me
*/
template isObservable(T)
{
    enum bool isObservable = is(typeof({
                T observable = T.init;
                alias E = T.ElementType;

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

/**
    Causes the given Observable to be well-behaved.
*/
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

/**
    Represents a value with no information.

    This struct is used as a fill-in when an $(D Observable) 
    would otherwise return void.
*/
struct Unit
{
}

/**
    Represents a notification of an event on an observable sequence.
*/
interface Notification(T)
{
@safe pure @property:

    /**
        Gets the kind of notification that this $(D Notification) represents.

        Returns:
            $(D value) returns a value when this returns $(D NotificationKind.onNext).

            $(D error) returns a value when this returns $(D NotificationKind.onError).
    */
    NotificationKind kind();

    /**
        Gets the value which caused the Observable sequence to emit this notification.
    */
    T value();

    /**
        Gets whether a $(D value) is available.

        Returns:
            `true` if $(D kind) is `onNext`, `false` otherwise.
    */
    bool hasValue();

    /**
        Gets the error which caused the underlying Observable to terminate.
    */
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

/**
    Represents a value and the time it was emitted from the source $(D Observable).
*/
struct Timestamp(T)
{
    /**
        The time this value was emitted.
    */
    SysTime timestamp;

    /**
        The value that was emitted.
    */
    T value;
}

/**
    Represents a value and the time since the last value was emitted from the source $(D Observable)
*/
struct TimeInterval(T)
{
    /**
        The time since the last event.
    */
    Duration duration;

    /**
        The value that was emitted.
    */
    T value;
}

/**
    Represents a value which has been zipped using the default behavior.
*/
struct Union(TLeft, TRight)
{
    /**
        The value from the left $(D Observable).
    */
    TLeft left;

    /**
        The value from the right $(D Observable).
    */
    TRight right;
}
