module reactived.observer;

/// Represents an Observer which listens on an Observable sequence.
interface Observer(T)
{
    /// Invoked when the next value in the Observable sequence is available.
    void onNext(T value);

    /// Invoked when the Observable sequence terminates due to an error.
    void onError(Throwable error);

    /// Invoked when the Observable sequence terminates successfully.
    void onCompleted();
}