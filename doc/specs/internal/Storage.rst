Storage
=======

Persistent storage is one of the main components of a DTN bundle router. RDTN
implements its storage using the Ruby ``PStore``, but the ``DBM`` module from
the Ruby standard library and even SQLite should be considered as well in the
future. The RDTN ``Storage`` class is implemented as a singleton, so that only
one store object exists in an instance of the RDTN daemon.

Bundles are the most important objects the store needs to take care of, but it
should also be able to make persistent copies of routing state (e.g. routing
tables or history of previous contacts) and link configurations.

Bundle payload should be stored independently of the primary bundle block and
other meta information. The meta data can be assumed to require less memory than
the payload and it can be used to find bundles when they are needed.

Events
------

The storage object subscribes the ``:bundleParsed`` event. When receiving the
event new bundle is inserted into the store.

Housekeeping
------------

The storage object starts a thread on initialization that searches the store
for expired bundles. Such bundles are deleted and the appropriate administrative
records are generated.
