module reactived.observable.fibers;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import reactived.util;

import core.thread;
/++
    Represents an Observer which also acts as a Fiber.

    When the FiberObserver's onCompleted method is called,
    it will set the value of the underlying ValueFiber to
    the last received value reported to onNext.

    Instantiating this class directly is not recommended.
    Use $(D toFiber) instead.
+/
class FiberObserver(T) : ValueFiber!T, Observer!T
{
    private
    {
        T _value;
    }

    void onNext(T value)
    {
        _value = value;
    }

    void onCompleted()
    {
        setValue(_value);
    }

    void onError(Throwable error)
    {
        setError(error);
    }
}

ValueFiber!T toFiber(T)(Observable!T source)
{
    auto fiber = new FiberObserver!T();
    source.subscribe(fiber);

    return fiber;
}

unittest
{
    import reactived.subject : Subject;

    Subject!int subject = new Subject!int();

    auto fiber = subject.toFiber();

    subject.onNext(1);
    fiber.call();
    assert(!fiber.hasValue);

    subject.onNext(2);
    fiber.call();
    assert(!fiber.hasValue);

    subject.onCompleted();

    fiber.call();
    assert(fiber.state == Fiber.State.TERM);
    assert(fiber.hasValue);

    assert(fiber.value == 2);
}
